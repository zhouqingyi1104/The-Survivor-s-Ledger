#!/usr/bin/env python3
"""Run the explicit offline Godot test manifest in a retained worktree snapshot.

Only the Python standard library is needed. No game process runs in the source
checkout, and a successful process exit alone is never a passing test.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import time
import uuid

WORKSPACE = Path(__file__).resolve().parent.parent
TIERS = ("fast", "core", "ui", "full")
SOURCE_ROOTS = ("assets", "data", "scripts", "scenes", "tests", "tools")
ROOT_FILES = ("project.godot", "export_presets.cfg")
SYSTEM_ENVIRONMENT = frozenset((
    "PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "NUMBER_OF_PROCESSORS", "OS",
    "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "XDG_RUNTIME_DIR", "LANG", "LANGUAGE",
    "LC_ALL", "LC_CTYPE", "LC_NUMERIC", "LC_TIME", "LC_COLLATE", "LC_MONETARY", "LC_MESSAGES",
    "LC_PAPER", "LC_NAME", "LC_ADDRESS", "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION",
))
CLEANUP_ERRORS = (
    re.compile(r"^ERROR: Texture with GL ID of \d+: leaked \d+ bytes\.$"),
    re.compile(r"^ERROR: \d+ resources still in use at exit \(run with --verbose for details\)\.$"),
)
ERROR_LINE = re.compile(r"\b(?:SCRIPT ERROR|ParseError|Parse Error|ERROR)\b", re.I)


class RunnerError(ValueError):
    """Invalid configuration, unsafe path, or unavailable local prerequisite."""


def _plain_path(path: Path, boundary: Path) -> Path:
    """Reject links/reparse points before resolving, including parent junctions."""
    path = Path(os.path.abspath(path))
    boundary = Path(os.path.abspath(boundary))
    try:
        path.relative_to(boundary)
    except ValueError as exc:
        raise RunnerError(f"Path escapes {boundary}: {path}") from exc
    for candidate in (path, *path.parents):
        if candidate.exists() or candidate.is_symlink():
            info = candidate.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
                raise RunnerError(f"Links/reparse points are not allowed: {candidate}")
    return path


def _entry(entry: object, workspace: Path, roots: tuple[str, ...] = ("tests",)) -> str:
    if not isinstance(entry, str) or "\\" in entry or ":" in entry:
        raise RunnerError(f"Invalid test entry: {entry!r}")
    relative = PurePosixPath(entry)
    if (relative.is_absolute() or not relative.parts or relative.parts[0] not in roots
            or any(part in ("", ".", "..") for part in entry.split("/"))):
        raise RunnerError(f"Entry must be a plain path inside {' or '.join(roots)}/: {entry!r}")
    actual = _plain_path(workspace / entry, workspace / relative.parts[0])
    if not actual.is_file():
        raise RunnerError(f"Test entry does not exist: {entry}")
    return entry


def load_manifest(path: Path, workspace: Path) -> dict:
    try:
        manifest = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        raise RunnerError(f"Cannot read manifest: {exc}") from exc
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise RunnerError("Manifest schema_version must be 1")
    if manifest.get("engine_version") != "4.7.2":
        raise RunnerError("Manifest engine_version must be 4.7.2")
    cases = manifest.get("cases")
    excluded = manifest.get("excluded")
    if not isinstance(cases, list) or not cases or not isinstance(excluded, list):
        raise RunnerError("Manifest requires nonempty cases and an excluded array")
    identifiers, entries = set(), set()
    for case in cases:
        if not isinstance(case, dict):
            raise RunnerError("Every case must be an object")
        identifier = case.get("id")
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", identifier):
            raise RunnerError(f"Invalid case ID: {identifier!r}")
        if identifier in identifiers:
            raise RunnerError(f"Duplicate case ID: {identifier}")
        identifiers.add(identifier)
        entry = _entry(case.get("entry"), workspace)
        if entry in entries:
            raise RunnerError(f"Duplicate entry: {entry}")
        entries.add(entry)
        if case.get("kind") not in ("scene", "script"):
            raise RunnerError(f"Invalid kind for {identifier}")
        expected_suffix = ".tscn" if case["kind"] == "scene" else ".gd"
        if not entry.endswith(expected_suffix):
            raise RunnerError(f"Entry/kind mismatch for {identifier}")
        if case.get("tier") not in TIERS or case.get("mode") not in ("headless", "window"):
            raise RunnerError(f"Invalid tier/mode for {identifier}")
        seconds = case.get("timeout_seconds")
        if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds <= 0:
            raise RunnerError(f"Invalid timeout_seconds for {identifier}")
        marker = case.get("success_regex")
        if not isinstance(marker, str) or not marker.strip():
            raise RunnerError(f"Missing success_regex for {identifier}")
        try:
            compiled = re.compile(marker, re.M)
        except re.error as exc:
            raise RunnerError(f"Invalid success_regex for {identifier}: {exc}") from exc
        if compiled.search(""):
            raise RunnerError(f"success_regex must require a completion marker: {identifier}")
        supported = case.get("platforms", ["Windows", "Linux"])
        if (not isinstance(supported, list) or not supported
                or any(item not in ("Windows", "Linux") for item in supported)
                or len(supported) != len(set(supported))):
            raise RunnerError(f"Invalid platforms for {identifier}")
    for item in excluded:
        if not isinstance(item, dict) or not isinstance(item.get("reason"), str) or not item["reason"].strip():
            raise RunnerError("Every excluded entry needs a reason")
        entry = _entry(item.get("entry"), workspace, ("tests", "tools"))
        if entry in entries:
            raise RunnerError(f"Duplicate/included exclusion: {entry}")
        entries.add(entry)
    return manifest


def select_cases(manifest: dict, tier: str, requested_ids: list[str], system: str) -> list[dict]:
    del system  # Platform exclusions remain in the selection and become explicit SKIP.
    if tier not in TIERS:
        raise RunnerError(f"Unknown tier: {tier}")
    requested = []
    for group in requested_ids:
        for identifier in group.split(","):
            identifier = identifier.strip()
            if not identifier:
                raise RunnerError("Empty case ID")
            if identifier in requested:
                raise RunnerError(f"Duplicate requested case ID: {identifier}")
            requested.append(identifier)
    by_id = {case["id"]: case for case in manifest["cases"]}
    if requested:
        unknown = [identifier for identifier in requested if identifier not in by_id]
        if unknown:
            raise RunnerError(f"Unknown case ID: {', '.join(unknown)}")
        return [by_id[identifier] for identifier in requested]
    tiers = {"fast": {"fast"}, "core": {"fast", "core"}, "ui": {"ui"}, "full": set(TIERS)}[tier]
    selected = [case for case in manifest["cases"] if case["tier"] in tiers]
    if not selected:
        raise RunnerError(f"Empty selection for tier {tier}")
    return selected


def classify_result(case: dict, exit_code: int | None, timed_out: bool, output: str) -> tuple[str, str, list[str]]:
    marker = re.search(case["success_regex"], output, re.M) if case.get("success_regex") else None
    warnings = []
    failure = None
    offset = 0
    for raw in output.splitlines(keepends=True):
        line = raw.strip()
        cleanup = any(pattern.fullmatch(line) for pattern in CLEANUP_ERRORS)
        # Cleanup exceptions apply only after this case actually reports completion.
        allowed = cleanup and marker is not None and offset >= marker.end()
        if allowed or re.match(r"^WARNING:", line):
            warnings.append(line)
        if ERROR_LINE.search(line) and not allowed and failure is None:
            failure = line
        offset += len(raw)
    if timed_out:
        return "FAIL", "Process exceeded its parent-enforced timeout", warnings
    if failure:
        return "FAIL", failure, warnings
    if exit_code != 0:
        return "FAIL", f"Process exited with code {exit_code}", warnings
    if case.get("success_regex") and marker is None:
        return "FAIL", "Required completion marker was not printed", warnings
    return ("PASS_WITH_WARNINGS" if warnings else "PASS"), "", warnings


def _git(workspace: Path, *args: str, data: bytes | None = None) -> bytes:
    result = subprocess.run(["git", "-C", str(workspace), *args], input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise RunnerError(f"Git command failed: {' '.join(args[:2])}: {result.stderr.decode('utf-8', 'replace').strip()}")
    return result.stdout


def snapshot_project(workspace: Path, destination: Path) -> dict:
    workspace = Path(workspace).resolve()
    destination = _plain_path(Path(destination), workspace / "build")
    if destination.exists():
        raise RunnerError(f"Snapshot destination already exists: {destination}")
    listed = _git(workspace, "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", *SOURCE_ROOTS, *ROOT_FILES)
    paths = sorted(set(path for path in listed.split(b"\0") if path))
    ignored_check = subprocess.run(["git", "-C", str(workspace), "check-ignore", "--no-index", "--stdin", "-z"],
                                   input=b"\0".join(paths) + b"\0", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if ignored_check.returncode not in (0, 1):
        raise RunnerError("Cannot verify snapshot ignore boundaries")
    ignored = set(ignored_check.stdout.split(b"\0"))
    destination.mkdir(parents=True)
    files, digest, excluded_count = [], hashlib.sha256(), 0
    for encoded in paths:
        name = encoded.decode("utf-8", "strict")
        relative = PurePosixPath(name)
        if (encoded in ignored or any(part in (".git", ".godot", "build", "__pycache__") for part in relative.parts)
                or any(part == ".env" or part.startswith(".env.") for part in relative.parts)
                or relative.name in ("Memory.md", "Memory.md.tmp") or relative.suffix in (".pyc", ".pyo")):
            excluded_count += 1
            continue
        source = _plain_path(workspace / name, workspace)
        if not source.exists():  # Tracked deletions are part of the current worktree.
            continue
        if not source.is_file():
            raise RunnerError(f"Snapshot source is not a regular file: {name}")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        checksum = hashlib.sha256(target.read_bytes()).hexdigest()
        files.append({"path": name, "sha256": checksum, "size": target.stat().st_size})
        digest.update(name.encode("utf-8") + b"\0" + checksum.encode("ascii") + b"\0")
    if not (destination / "project.godot").is_file():
        raise RunnerError("Snapshot is missing project.godot")
    build = destination / "build"
    build.mkdir()
    (build / ".gdignore").write_text("", encoding="utf-8")
    return {"files": files, "digest": digest.hexdigest(), "excluded_count": excluded_count}


def isolated_environment(project: Path, identifier: str) -> dict:
    base = project / "build" / "test-runs" / identifier
    # Inheriting custom test filters, output paths, or provider credentials can
    # turn a complete offline test into a partial run or an external operation.
    env = {key: value for key, value in os.environ.items()
           if key.upper() in SYSTEM_ENVIRONMENT or key.upper().startswith("PROCESSOR_")}
    home = base / "home"
    home.mkdir(parents=True, exist_ok=True)
    env.update({"USERNAME": "ledger_test_user", "USER": "ledger_test_user",
                "HOME": str(home), "USERPROFILE": str(home)})
    for key, name in (("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"),
                      ("XDG_DATA_HOME", "xdg-data"), ("XDG_CONFIG_HOME", "xdg-config"),
                      ("XDG_CACHE_HOME", "xdg-cache"), ("TEMP", "tmp"), ("TMP", "tmp"), ("TMPDIR", "tmp")):
        target = base / name
        target.mkdir(parents=True, exist_ok=True)
        env[key] = str(target)
    return env


def run_process(command: list[str], cwd: Path, env: dict, timeout: float, log_path: Path) -> dict:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    timed_out, cleanup_error, exit_code = False, "", None
    options = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
    with log_path.open("wb") as stream:
        try:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                       stdout=stream, stderr=subprocess.STDOUT, **options)
        except OSError as exc:
            stream.write(f"Runner could not start process: {exc}\n".encode("utf-8"))
        else:
            try:
                exit_code = process.wait(timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
                timed_out = isinstance(exc, subprocess.TimeoutExpired)
                try:
                    if os.name == "nt":
                        killed = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
                                                creationflags=subprocess.CREATE_NO_WINDOW)
                        if killed.returncode and process.poll() is None:
                            cleanup_error = killed.stderr.decode("utf-8", "replace")
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except (OSError, subprocess.TimeoutExpired) as error:
                    cleanup_error = str(error)
                try:
                    exit_code = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    exit_code = process.wait(timeout=10)
                    cleanup_error = cleanup_error or "Process tree termination required a fallback"
                if isinstance(exc, KeyboardInterrupt):
                    raise
    return {"command": command, "exit_code": exit_code, "timed_out": timed_out,
            "duration_seconds": round(time.monotonic() - started, 3), "log": str(log_path),
            "output": log_path.read_bytes().decode("utf-8", "replace"), "cleanup_error": cleanup_error}


def _engine(value: str | None, workspace: Path) -> Path:
    default = workspace / "tools/godot/Godot_v4.7.2-stable_win64_console.exe" if os.name == "nt" else None
    found = value or (str(default) if default and default.is_file() else shutil.which("godot") or shutil.which("godot4"))
    if not found:
        raise RunnerError("Godot 4.7.2 is not available; specify the existing binary with --godot")
    path = Path(found)
    if not path.is_absolute():
        path = workspace / path
    if not path.is_file():
        raise RunnerError(f"Godot binary does not exist: {path}")
    return path.resolve()


def _rerun(case_id: str, args: argparse.Namespace) -> str:
    command = [sys.executable, str(WORKSPACE / "tools/run_tests.py"), "--case", case_id]
    if args.godot:
        command.extend(["--godot", args.godot])
    if args.manifest:
        command.extend(["--manifest", args.manifest])
    return subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tier", choices=TIERS, default="fast")
    parser.add_argument("--case", action="append", default=[], dest="case_ids")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--godot")
    parser.add_argument("--output-root", default="build/test-runs")
    parser.add_argument("--manifest")
    parser.add_argument("--import-timeout", type=float, default=240)
    args = parser.parse_args(argv)
    workspace = WORKSPACE.resolve()
    try:
        if not math.isfinite(args.import_timeout) or args.import_timeout <= 0:
            raise RunnerError("--import-timeout must be finite and positive")
        manifest_path = Path(args.manifest) if args.manifest else workspace / "tools/test_manifest.json"
        if not manifest_path.is_absolute():
            manifest_path = workspace / manifest_path
        manifest = load_manifest(manifest_path, workspace)
        system = platform.system()
        selected = select_cases(manifest, args.tier, args.case_ids, system)
        if args.list:
            for case in selected:
                skip = " [SKIP: platform]" if system not in case.get("platforms", ["Windows", "Linux"]) else ""
                print(f"{case['id']}\t{case['tier']}\t{case['mode']}\t{case['entry']}{skip}")
            return 0
        runnable = any(system in case.get("platforms", ["Windows", "Linux"]) for case in selected)
        engine = _engine(args.godot, workspace) if runnable else None
        output_root = Path(args.output_root)
        if not output_root.is_absolute():
            output_root = workspace / output_root
        output_root = _plain_path(output_root, workspace / "build")
        run_root = output_root / uuid.uuid4().hex
        run_root.mkdir(parents=True)
    except (OSError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 2

    project = run_root / "project"
    report = {"schema_version": 1, "tier": args.tier, "platform": system, "engine": str(engine) if engine else None,
              "manifest": str(manifest_path), "snapshot": None, "first_failure": None,
              "selection": [{**case, "status": "SKIP" if system not in case.get("platforms", ["Windows", "Linux"]) else "NOT_RUN",
                             "reason": "Unsupported platform" if system not in case.get("platforms", ["Windows", "Linux"]) else "Not started"} for case in selected]}
    try:
        if not runnable:
            raise RunnerError(f"No runnable cases for {system}; every selected case is SKIP")
        report["source_sha"] = _git(workspace, "rev-parse", "HEAD").decode().strip()
        report["source_status_before"] = _git(workspace, "status", "--porcelain=v1", "-z").decode("utf-8", "replace").split("\0")
        report["snapshot_files"] = snapshot_project(workspace, project)
        report["snapshot"] = str(project)
        report["source_status_after"] = _git(workspace, "status", "--porcelain=v1", "-z").decode("utf-8", "replace").split("\0")
        report["source_dirty"] = any(report["source_status_before"])
        report["source_status_changed_during_snapshot"] = report["source_status_before"] != report["source_status_after"]
        report["source_boundary"] = "Current worktree files, including eligible untracked/modified source; per-file hashes describe the retained snapshot, not an atomic or clean commit build"
        version = run_process([str(engine), "--version"], project, isolated_environment(project, "version"), 20, run_root / "version.log")
        report["version"] = version
        if version["exit_code"] != 0 or version["timed_out"] or not re.fullmatch(r"4\.7\.2\.stable\.[^\s]+", version["output"].strip()):
            raise RunnerError("Expected Godot 4.7.2.stable; see version.log")
        imported = run_process([str(engine), "--headless", "--editor", "--path", str(project), "--import", "--quit"],
                               project, isolated_environment(project, "import"), args.import_timeout, run_root / "import.log")
        import_status, import_reason, import_warnings = classify_result({}, imported["exit_code"], imported["timed_out"], imported["output"])
        report["import"] = {**imported, "status": import_status, "reason": import_reason, "warnings": import_warnings}
        if import_status == "FAIL" or imported["cleanup_error"]:
            raise RunnerError(f"Resource import: {import_reason or imported['cleanup_error']}")
        for result in report["selection"]:
            if result["status"] == "SKIP":
                continue
            command = [str(engine), "--path", str(project), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility"]
            if result["mode"] == "headless":
                command.append("--headless")
            else:
                command.extend(["--resolution", "1280x720"])
            if result["kind"] == "script":
                command.append("--script")
            command.append("res://" + result["entry"])
            process = run_process(command, project, isolated_environment(project, result["id"]), result["timeout_seconds"], run_root / "logs" / (result["id"] + ".log"))
            status, reason, warnings = classify_result(result, process["exit_code"], process["timed_out"], process["output"])
            if process["cleanup_error"]:
                status, reason = "FAIL", "Process cleanup: " + process["cleanup_error"]
            result.update({**process, "status": status, "reason": reason, "warnings": warnings})
            if status == "FAIL":
                report["first_failure"] = {"id": result["id"], "reason": reason, "rerun": _rerun(result["id"], args)}
                break
    except (OSError, ValueError, KeyboardInterrupt) as exc:
        report["first_failure"] = {"id": "runner", "reason": str(exc) or "Interrupted", "rerun": None}
    report_path = run_root / "results.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = {status: sum(case["status"] == status for case in report["selection"]) for status in ("PASS", "PASS_WITH_WARNINGS", "FAIL", "NOT_RUN", "SKIP")}
    print(" ".join(f"{status}={count}" for status, count in counts.items()))
    print(f"Report: {report_path}")
    failure = report["first_failure"]
    if failure:
        print(f"First failure: {failure['id']}: {failure['reason']}")
        if failure["rerun"]:
            print(f"Rerun: {failure['rerun']}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
