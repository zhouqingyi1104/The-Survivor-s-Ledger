"""Unit tests for the C0 process/evidence launcher; fixtures are not game captures."""
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools' / 'test_courtyard_scenery.py'


def module():
    spec = importlib.util.spec_from_file_location('c0_runner', SCRIPT)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


class RunnerTests(unittest.TestCase):
    def setUp(self):
        (ROOT / '.hermes').mkdir(exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix='c0-runner-unit-', dir=ROOT / '.hermes')
        self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name)

    def test_entrypoint_exists(self):
        self.assertTrue(SCRIPT.is_file(), 'C0 reproducible launcher must be in the repository')

    def test_paths_resolve_from_repository(self):
        r = module()
        self.assertEqual(pathlib.Path(r.PROJECT), ROOT)
        self.assertTrue(pathlib.Path(r.GODOT).is_absolute())

    def test_process_exit_and_missing_marker_are_not_success(self):
        r = module()
        r.GODOT = sys.executable
        code, log, _ = r.run('unit-exit-seven', ['-c', 'raise SystemExit(7)'], 5, str(self.base))
        self.assertEqual(code, 7)
        self.assertFalse(r.marker_ok(log, 0))

    def test_timeout_is_nonzero_and_bounded(self):
        r = module()
        r.GODOT = sys.executable
        code, _, elapsed = r.run('unit-timeout', ['-c', 'import time;time.sleep(5)'], 0.15, str(self.base))
        self.assertEqual(code, 124)
        self.assertLess(elapsed, 4)

    def test_incomplete_manifest_is_rejected(self):
        r = module()
        # Deliberately incomplete unit fixture, never labelled as a game capture.
        (self.base / 'shots_manifest.json').write_text(json.dumps({'saved': 0, 'total': 16, 'shots': []}), encoding='utf-8')
        self.assertFalse(r.validate_shots(str(self.base), (1280, 720)))

    def test_per_run_user_data_isolated(self):
        r = module()
        a = r.make_env(str(self.base / 'a'))
        b = r.make_env(str(self.base / 'b'))
        for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'TMP'):
            self.assertNotEqual(a[key], b[key])
            self.assertTrue(pathlib.Path(a[key]).is_relative_to(self.base / 'a'))

    def test_unique_run_directories(self):
        r = module()
        r.ROOT = str(self.base)
        a = pathlib.Path(r.new_run_dir('unit'))
        b = pathlib.Path(r.new_run_dir('unit'))
        self.assertNotEqual(a, b)
        self.assertTrue(a.is_dir() and b.is_dir())


if __name__ == '__main__':
    unittest.main()
