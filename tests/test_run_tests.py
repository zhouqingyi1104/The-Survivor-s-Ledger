"""Adversarial checks for C5's test launcher, using no Godot or player data.

These synthetic processes verify the launcher contract, not game behavior.
Run with: python -m unittest discover -s tests -p test_run_tests.py -v
"""
import contextlib
import ctypes
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "run_tests.py"


def load_runner():
    spec = importlib.util.spec_from_file_location("c5_test_runner", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def case(case_id="first", tier="fast", platforms=None):
    return {
        "id": case_id,
        "entry": "tests/fixture.tscn",
        "kind": "scene",
        "tier": tier,
        "mode": "headless",
        "timeout_seconds": 30,
        "success_regex": r"\[fixture\] complete: 0 failures",
        "platforms": platforms or ["Windows", "Linux"],
    }


def manifest(cases=None):
    return {
        "schema_version": 1,
        "engine_version": "4.7.2",
        "cases": cases if cases is not None else [case()],
        "excluded": [],
    }


def write_text(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")


def prepare_workspace(path):
    """A small real Git checkout with both source and forbidden local data."""
    path.mkdir(parents=True)
    subprocess.run(["git", "init", "--quiet", str(path)], check=True,
                   capture_output=True)
    write_text(path / ".gitignore", "/build/\n/Memory.md\n/Memory.md.tmp\n/assets/private/\n")
    write_text(path / "project.godot", "config_version=5\n")
    write_text(path / "tests/fixture.tscn", "[gd_scene format=3]\n[node name=\"fixture\" type=\"Node\"]\n")
    write_text(path / "scripts/tracked.gd", "extends Node\n")
    subprocess.run(["git", "-C", str(path), "add", ".gitignore", "project.godot",
                    "tests/fixture.tscn", "scripts/tracked.gd"], check=True,
                   capture_output=True)
    write_text(path / "scripts/untracked_feature.gd", "extends RefCounted\n")
    write_text(path / "Memory.md", "PLAYER ARCHIVE MUST NOT MOVE\n")
    write_text(path / "Memory.md.tmp", "PLAYER TEMP MUST NOT MOVE\n")
    write_text(path / ".env", "SYNTHETIC_SECRET=fixture\n")
    write_text(path / ".env.local", "SYNTHETIC_SECRET=fixture-local\n")
    write_text(path / "scripts/.env", "SYNTHETIC_SECRET=fixture-source-root\n")
    write_text(path / "tools/.env.local", "SYNTHETIC_SECRET=fixture-tools-root\n")
    write_text(path / "assets/private/model.glb", "synthetic private model\n")
    write_text(path / "build/previous/evidence.txt", "prior evidence\n")
    return path.resolve()


def pid_alive(pid):
    if os.name == "nt":
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_bool, ctypes.c_ulong]
        kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        try:
            code = ctypes.c_ulong()
            return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
        finally:
            kernel.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # A killed descendant may remain a zombie until its init process reaps it.
    status = Path("/proc") / str(pid) / "stat"
    if status.exists():
        return status.read_text().split(")", 1)[1].split()[0] != "Z"
    return True


def directory_link(link, target):
    """Create a real reparse fixture on Windows even without symlink privilege."""
    try:
        link.symlink_to(target, target_is_directory=True)
    except OSError:
        if os.name != "nt":
            raise
        created = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)],
                                 capture_output=True, text=True)
        if created.returncode:
            raise unittest.SkipTest("host does not permit synthetic symlinks or junctions")


def remove_directory_link(link):
    # Remove the link only, never recurse into the external target.
    if link.is_symlink():
        link.unlink()
    elif link.exists():
        link.rmdir()


class RunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = load_runner()


class ClassificationTests(RunnerTests):
    def test_only_clean_completion_passes(self):
        status, _, warnings = self.runner.classify_result(
            case(), 0, False, "[fixture] complete: 0 failures\n")
        self.assertEqual(status, "PASS")
        self.assertEqual(warnings, [])

    def test_exit_zero_with_errors_or_no_completion_fails(self):
        marker = "[fixture] complete: 0 failures\n"
        for output in (
            "SCRIPT ERROR: Invalid call at function test\n" + marker,
            "ParseError: expected end of statement\n" + marker,
            "ERROR: Unknown engine failure\n" + marker,
            "Godot started and exited without a result\n",
            "[fixture] complete: 1 failures\n",
        ):
            with self.subTest(output=output):
                status, reason, _ = self.runner.classify_result(case(), 0, False, output)
                self.assertEqual(status, "FAIL")
                self.assertTrue(reason)

    def test_process_failure_beats_completion_marker(self):
        for exit_code, timed_out in ((7, False), (-9, False), (0, True), (None, True)):
            with self.subTest(exit_code=exit_code, timed_out=timed_out):
                status, reason, _ = self.runner.classify_result(
                    case(), exit_code, timed_out, "[fixture] complete: 0 failures\n")
                self.assertEqual(status, "FAIL")
                self.assertTrue(reason)

    def test_cleanup_messages_preserve_warning_and_cannot_hide_other_errors(self):
        marker = "[fixture] complete: 0 failures\n"
        cleanup = (
            "WARNING: 4 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
            "   at: cleanup (core/object/object.cpp:2536)\n"
            "ERROR: 2 resources still in use at exit (run with --verbose for details).\n"
            "   at: clear (core/io/resource.cpp:822)\n"
            "ERROR: Texture with GL ID of 32: leaked 349524 bytes.\n"
        )
        status, _, warnings = self.runner.classify_result(case(), 0, False, marker + cleanup)
        self.assertEqual(status, "PASS_WITH_WARNINGS")
        self.assertTrue(warnings)
        self.assertIn("resources still in use", "\n".join(warnings))
        for suffix in ("SCRIPT ERROR: unrelated crash\n", "ERROR: unrelated failure\n",
                       "ERROR: 2 resources still in use at exit INVALID\n",
                       "ERROR: Texture with GL ID of 32: leaked 349524 bytes. ALSO FAILED\n"):
            with self.subTest(suffix=suffix):
                status, _, _ = self.runner.classify_result(case(), 0, False, marker + cleanup + suffix)
                self.assertEqual(status, "FAIL")
        status, _, _ = self.runner.classify_result(case(), 0, False, cleanup)
        self.assertEqual(status, "FAIL", "cleanup warnings do not replace the completion marker")


class ManifestAndSelectionTests(RunnerTests):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ledger-c5-manifest-")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        write_text(self.workspace / "tests/fixture.tscn", "fixture\n")
        self.path = self.workspace / "manifest.json"

    def load(self, value):
        self.path.write_text(json.dumps(value), encoding="utf-8")
        return self.runner.load_manifest(self.path, self.workspace)

    def test_valid_manifest_loads(self):
        loaded = self.load(manifest())
        self.assertEqual([entry["id"] for entry in loaded["cases"]], ["first"])

    def test_invalid_configuration_rejected_before_execution(self):
        changes = (
            ("success_regex", "["),
            ("success_regex", ""),
            ("success_regex", ".*"),
            ("platforms", []),
            ("platforms", ["windows"]),
            ("platforms", ["Windows", "Windows"]),
            ("platforms", "Windows"),
            ("tier", "fulll"),
            ("mode", "auto"),
            ("timeout_seconds", 0),
            ("timeout_seconds", True),
            ("entry", "../outside.tscn"),
            ("entry", str(self.workspace / "tests/fixture.tscn")),
            ("entry", "tests/missing.tscn"),
        )
        for key, value in changes:
            candidate = manifest()
            candidate["cases"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.load(candidate)

    def test_tools_exclusion_is_documented_but_cannot_escape_its_roots(self):
        write_text(self.workspace / "tools/special.py", "# synthetic diagnostic\n")
        value = manifest()
        value["excluded"] = [{"entry": "tools/special.py", "reason": "Requires a manual screenshot"}]
        self.assertEqual(self.load(value)["excluded"][0]["entry"], "tools/special.py")
        write_text(self.workspace / "outside.py", "# outside allowed entry roots\n")
        for entry in ("tools/../outside.py", "../outside.py", str(self.workspace / "outside.py")):
            value["excluded"][0]["entry"] = entry
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                self.load(value)

    def test_excluded_symlink_is_rejected(self):
        external = self.workspace / "outside"
        write_text(external / "diagnostic.py", "# must not be followed\n")
        link = self.workspace / "tools/linked"
        link.parent.mkdir(exist_ok=True)
        directory_link(link, external)
        value = manifest()
        value["excluded"] = [{"entry": "tools/linked/diagnostic.py", "reason": "Synthetic exclusion"}]
        try:
            with self.assertRaises(ValueError):
                self.load(value)
        finally:
            remove_directory_link(link)
        for candidate in (manifest([]), manifest([case(), case()]),
                          {**manifest(), "schema_version": 999},
                          {**manifest(), "engine_version": "latest"}):
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                self.load(candidate)

    def test_selection_is_explicit_and_platform_skip_stays_visible(self):
        value = manifest([case("fast"), case("core", "core"),
                          {**case("window", "ui"), "mode": "windowed"},
                          case("windows_only", platforms=["Windows"])])
        ids = lambda selected: [entry["id"] for entry in selected]
        self.assertEqual(ids(self.runner.select_cases(value, "fast", [], "Linux")),
                         ["fast", "windows_only"])
        self.assertEqual(ids(self.runner.select_cases(value, "core", [], "Linux")),
                         ["fast", "core", "windows_only"])
        self.assertEqual(ids(self.runner.select_cases(value, "ui", [], "Linux")), ["window"])
        self.assertEqual(ids(self.runner.select_cases(value, "full", [], "Linux")),
                         ["fast", "core", "window", "windows_only"])
        self.assertEqual(ids(self.runner.select_cases(value, "fast", ["core"], "Linux")), ["core"])

    def test_unknown_duplicate_and_empty_selection_rejected(self):
        value = manifest()
        for tier, requested in (("fast", ["unknown"]), ("fast", ["first", "first"]),
                                ("fast", [""]), ("typo", []), ("ui", [])):
            with self.subTest(tier=tier, requested=requested), self.assertRaises(ValueError):
                self.runner.select_cases(value, tier, requested, "Linux")


class SnapshotTests(RunnerTests):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ledger-c5-snapshot-")
        self.addCleanup(self.temp.cleanup)
        self.workspace = prepare_workspace(Path(self.temp.name) / "workspace")
        self.destination = self.workspace / "build/test-runs/run/project"

    def test_snapshot_includes_current_source_and_preserves_local_player_data(self):
        original = (self.workspace / "Memory.md").read_bytes()
        result = self.runner.snapshot_project(self.workspace, self.destination)
        self.assertTrue((self.destination / "project.godot").is_file())
        self.assertTrue((self.destination / "scripts/tracked.gd").is_file())
        self.assertTrue((self.destination / "scripts/untracked_feature.gd").is_file())
        for forbidden in ("Memory.md", "Memory.md.tmp", ".env", ".env.local", ".git",
                          "scripts/.env", "tools/.env.local",
                          "assets/private/model.glb", "build/previous/evidence.txt"):
            with self.subTest(forbidden=forbidden):
                self.assertFalse((self.destination / forbidden).exists())
        self.assertEqual((self.workspace / "Memory.md").read_bytes(), original)
        write_text(self.destination / "scripts/tracked.gd", "fixture modified its snapshot\n")
        self.assertEqual((self.workspace / "scripts/tracked.gd").read_text(), "extends Node\n")
        self.assertTrue(result["digest"])
        self.assertIn("scripts/untracked_feature.gd", [entry["path"] for entry in result["files"]])

    def test_destination_cannot_escape_build_or_overwrite_source(self):
        for destination in (Path(self.temp.name) / "outside", self.workspace,
                            self.workspace / "scripts/replacement"):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                self.runner.snapshot_project(self.workspace, destination)
        self.assertTrue((self.workspace / "scripts/tracked.gd").exists())

    def test_tracked_local_files_do_not_bypass_privacy_exclusions(self):
        write_text(self.workspace / "scripts/.env", "SYNTHETIC_SECRET=nested\n")
        write_text(self.workspace / "scripts/Memory.md", "nested player archive\n")
        subprocess.run(["git", "-C", str(self.workspace), "add", "-f", "assets/private/model.glb",
                        "scripts/.env", "scripts/Memory.md"], check=True, capture_output=True)
        self.runner.snapshot_project(self.workspace, self.destination)
        for forbidden in ("assets/private/model.glb", "scripts/.env", "scripts/Memory.md"):
            with self.subTest(forbidden=forbidden):
                self.assertFalse((self.destination / forbidden).exists())

    def test_symlink_or_windows_junction_is_rejected(self):
        external = Path(self.temp.name) / "external"
        external.mkdir()
        write_text(external / "private.txt", "do not follow this fixture link\n")
        link = self.workspace / "scripts/external"
        directory_link(link, external)
        try:
            with self.assertRaises(ValueError):
                self.runner.snapshot_project(self.workspace, self.destination)
            self.assertEqual((external / "private.txt").read_text(), "do not follow this fixture link\n")
        finally:
            remove_directory_link(link)


class EnvironmentIsolationTests(RunnerTests):
    def test_children_do_not_inherit_secrets_filters_or_external_output_paths(self):
        with tempfile.TemporaryDirectory(prefix="ledger-c5-env-") as temporary:
            project = Path(temporary).resolve() / "project"
            project.mkdir()
            hostile = {
                "ARK_API_KEY": "synthetic-ark-credential",
                "OPENAI_API_KEY": "synthetic-openai-credential",
                "JOURNEY_ONLY": "filter-out-most-tests",
                "C1_SHOT": "D:/synthetic-external/capture.png",
                "C6_SCREENSHOT": "D:/synthetic-external/another.png",
                "USERNAME": "", "USER": "",
                "HOME": "D:/synthetic-player-home",
                "USERPROFILE": "D:/synthetic-player-profile",
            }
            with patch.dict(os.environ, hostile):
                original = dict(os.environ)
                first = self.runner.isolated_environment(project, "first")
                second = self.runner.isolated_environment(project, "second")
                self.assertEqual(dict(os.environ), original, "the caller environment must remain intact")
            for key in ("ARK_API_KEY", "OPENAI_API_KEY", "JOURNEY_ONLY", "C1_SHOT", "C6_SCREENSHOT"):
                self.assertNotIn(key, first)
            self.assertTrue(first.get("USERNAME"))
            self.assertTrue(first.get("USER"))
            for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME",
                        "XDG_CACHE_HOME", "TEMP", "TMP", "TMPDIR", "HOME", "USERPROFILE"):
                with self.subTest(key=key):
                    self.assertTrue(Path(first[key]).is_relative_to(project / "build/test-runs/first"))
                    self.assertTrue(Path(second[key]).is_relative_to(project / "build/test-runs/second"))
                    self.assertNotEqual(first[key], second[key])
                    self.assertTrue(Path(first[key]).is_dir())


class RealProcessTests(RunnerTests):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ledger-c5-process-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def test_exit_code_and_complete_combined_unicode_log(self):
        script = self.work / "fixture.py"
        write_text(script, "import sys\nprint('stdout 完整', flush=True)\n"
                   "print('stderr 完整', file=sys.stderr, flush=True)\nsys.exit(7)\n")
        env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
        log = self.work / "fixture.log"
        result = self.runner.run_process([sys.executable, str(script)], self.work, env, 10, log)
        self.assertEqual(result["exit_code"], 7)
        self.assertFalse(result["timed_out"])
        for message in ("stdout 完整", "stderr 完整"):
            self.assertIn(message, result["output"])
            self.assertIn(message, log.read_text(encoding="utf-8"))

    def test_timeout_kills_parent_child_and_grandchild(self):
        script = self.work / "tree.py"
        pids = self.work / "pids"
        pids.mkdir()
        write_text(script,
                   "import os, pathlib, subprocess, sys, time\n"
                   "depth = int(sys.argv[1]); root = pathlib.Path(sys.argv[2])\n"
                   "(root / str(depth)).write_text(str(os.getpid()))\n"
                   "if depth < 2:\n"
                   "    subprocess.Popen([sys.executable, __file__, str(depth + 1), str(root)])\n"
                   "print('depth=' + str(depth), flush=True)\n"
                   "time.sleep(60)\n")
        result = None
        known_pids = []
        try:
            result = self.runner.run_process([sys.executable, str(script), "0", str(pids)],
                                             self.work, dict(os.environ), 3, self.work / "tree.log")
            known_pids = [int(path.read_text()) for path in pids.iterdir()]
            self.assertEqual(len(known_pids), 3, "fixture must create the entire descendant tree")
            self.assertTrue(result["timed_out"])
            self.assertLess(result["duration_seconds"], 15)
            deadline = time.monotonic() + 5
            while any(pid_alive(pid) for pid in known_pids) and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertEqual([pid for pid in known_pids if pid_alive(pid)], [],
                             "a timed out process must leave no live child or grandchild")
            self.assertIn("depth=0", (self.work / "tree.log").read_text(encoding="utf-8"))
        finally:
            # Failing the contract must not leave synthetic 60-second sleepers.
            if not known_pids:
                known_pids = [int(path.read_text()) for path in pids.iterdir()]
            for pid in known_pids:
                if pid_alive(pid):
                    if os.name == "nt":
                        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                                       capture_output=True)
                    else:
                        with contextlib.suppress(ProcessLookupError):
                            os.kill(pid, signal.SIGKILL)


class MainIntegrationTests(RunnerTests):
    """Real temporary Git/snapshot/report flow with a synthetic engine adapter."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ledger-c5-main-")
        self.addCleanup(self.temp.cleanup)
        self.workspace = prepare_workspace(Path(self.temp.name) / "workspace")
        hooks = Path(self.temp.name) / "empty-hooks"
        hooks.mkdir()
        subprocess.run(["git", "-C", str(self.workspace), "-c", "user.name=C5 Fixture",
                        "-c", "user.email=c5-fixture@example.invalid", "-c", "commit.gpgsign=false",
                        "-c", "core.hooksPath=" + str(hooks), "commit", "--quiet", "-m", "fixture"],
                       check=True, capture_output=True)
        self.manifest_path = self.workspace / "fixture_manifest.json"
        self.engine = self.workspace / "fake-engine"
        write_text(self.engine, "synthetic engine never executed\n")

    def invoke(self, value, adapter):
        self.manifest_path.write_text(json.dumps(value), encoding="utf-8")
        with patch.object(self.runner, "WORKSPACE", self.workspace), \
                patch.object(self.runner.platform, "system", return_value="Linux"), \
                patch.object(self.runner, "run_process", side_effect=adapter) as launched, \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = self.runner.main(["--manifest", str(self.manifest_path), "--godot", str(self.engine)])
        reports = list((self.workspace / "build/test-runs").glob("*/results.json"))
        self.assertEqual(len(reports), 1)
        return code, json.loads(reports[0].read_text(encoding="utf-8")), launched

    def result(self, command, cwd, env, timeout, log_path, output):
        self.assertTrue(Path(cwd).is_relative_to(self.workspace / "build/test-runs"))
        self.assertNotEqual(Path(cwd), self.workspace)
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME",
                    "XDG_CACHE_HOME", "TEMP", "TMP", "TMPDIR"):
            self.assertTrue(Path(env[key]).is_relative_to(Path(cwd) / "build/test-runs"), key)
        write_text(Path(log_path), output)
        return {"command": command, "exit_code": 0, "timed_out": False,
                "duration_seconds": 0.01, "log": str(log_path), "output": output,
                "cleanup_error": ""}

    def test_first_failure_stops_execution_and_keeps_later_not_run(self):
        first, second = case(), case("second")
        second["entry"] = "tests/second.tscn"
        write_text(self.workspace / second["entry"], "fixture\n")

        def adapter(command, cwd, env, timeout, log_path):
            if "--version" in command:
                output = "4.7.2.stable.fixture\n"
            elif "--import" in command:
                output = "Resource import complete\n"
            else:
                self.assertEqual(command[-1], "res://tests/fixture.tscn")
                output = "SCRIPT ERROR: fixture error despite exit zero\n[fixture] complete: 0 failures\n"
            return self.result(command, cwd, env, timeout, log_path, output)

        code, report, launched = self.invoke(manifest([first, second]), adapter)
        self.assertEqual(code, 1)
        self.assertEqual(launched.call_count, 3, "version, import and first case only")
        self.assertEqual([entry["status"] for entry in report["selection"]], ["FAIL", "NOT_RUN"])
        self.assertEqual(report["first_failure"]["id"], "first")
        self.assertIn("--case", report["first_failure"]["rerun"])
        self.assertIn("SCRIPT ERROR", report["selection"][0]["output"])
        self.assertEqual((self.workspace / "Memory.md").read_text(), "PLAYER ARCHIVE MUST NOT MOVE\n")

    def test_all_platform_skips_cannot_claim_success_or_start_engine(self):
        def forbidden(*args, **kwargs):
            self.fail("No engine may launch when every selected case is unsupported")

        code, report, launched = self.invoke(manifest([case(platforms=["Windows"])]), forbidden)
        self.assertEqual(code, 1)
        launched.assert_not_called()
        self.assertEqual([entry["status"] for entry in report["selection"]], ["SKIP"])
        self.assertIsNone(report["snapshot"])
        self.assertIsNotNone(report["first_failure"])

    def test_wrong_engine_version_prevents_import_and_all_test_execution(self):
        def adapter(command, cwd, env, timeout, log_path):
            self.assertIn("--version", command)
            return self.result(command, cwd, env, timeout, log_path, "4.6.1.stable.fixture\n")

        code, report, launched = self.invoke(manifest(), adapter)
        self.assertEqual(code, 1)
        self.assertEqual(launched.call_count, 1)
        self.assertEqual(report["selection"][0]["status"], "NOT_RUN")
        self.assertIn("4.7.2", report["first_failure"]["reason"])


if __name__ == "__main__":
    unittest.main()
