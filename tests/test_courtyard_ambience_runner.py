"""Unit tests for the C1 ambience process/evidence launcher; fixtures are synthetic.

Only these unit fixtures are synthetic. Real game evidence must come from a
Godot capture; the validator recomputes every pixel statistic from the PNG
bytes, so a manifest cannot claim warmth that the file does not contain.
"""
import importlib.util
import json
import os
import pathlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools' / 'test_courtyard_ambience.py'

WARM = (255, 205, 120)      # satisfies r>110, r-b>45, r-g>15
BASE = (205, 205, 210)      # snowy gray base (all channels > 200 -> "white")
DARK = (150, 150, 160)
PRE_TINT = (196, 200, 206)
NAV_POINTS = {'court': 3, 'north_inner': 15, 'south_w_inner': 5,
              'south_e_inner': 5, 'west_inner': 8, 'east_inner': 6}
WARM_COUNTS = {  # warm block count for natural night-like entries
    'ps_night_front': 220, 'ps_dusk_north': 120, 'ps_night_north_on': 400,
    'ph_night_court': 220, 'ph_blood_north': 300, 'pre_night_north': 300,
}


def module():
    spec = importlib.util.spec_from_file_location('c1_runner', SCRIPT)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


def _paint(base, dims, warm_k=0, heavy=False, pre=False):
    """Render a synthetic frame; warm blocks are 4x4 aligned -> exactly
    warm_k step-4 warm samples (same grid the GDScript/PIL diags use)."""
    from PIL import Image, ImageDraw
    w, h = dims
    fill = PRE_TINT if pre else BASE
    img = Image.new('RGB', dims, fill)
    dr = ImageDraw.Draw(img)
    if warm_k:
        per_row = (w + 3) // 4
        for k in range(warm_k):
            gx, gy = (k % per_row) * 4, (k // per_row) * 4
            dr.rectangle([gx, gy, gx + 3, gy + 3], fill=WARM)
    if heavy:
        for k in range(8):
            gx, gy = 600 + k * 20, 680
            dr.rectangle([gx, gy, gx + 3, gy + 3], fill=DARK)
    return img


def _lum_diff_files(a_path, b_path):
    from PIL import Image
    a = Image.open(a_path).convert('RGB').resize((160, 90), Image.BILINEAR)
    b = Image.open(b_path).convert('RGB').resize((160, 90), Image.BILINEAR)
    pa, pb = a.load(), b.load()
    total = n = 0
    for y in range(0, 90, 2):
        for x in range(0, 160, 2):
            ca, cb = pa[x, y], pb[x, y]
            total += abs((0.3*ca[0] + 0.59*ca[1] + 0.11*ca[2])
                         - (0.3*cb[0] + 0.59*cb[1] + 0.11*cb[2])) / 255.0
            n += 1
    return total / n


def write_fixture(target_dir, dims, state_correct=True, include_focus=True,
                  ablation_gain=True):
    """Build a manifest+PNG evidence set consistent with the launcher MATRIX."""
    r = module()
    target_dir.mkdir(parents=True, exist_ok=True)
    shots = []
    first_ref = {}
    for stem, focus, phase, snow, preset, yaw, pitch, dist, qa_off in r.MATRIX:
        png = stem + '.png'
        warm_k = WARM_COUNTS.get(stem, 0)
        if qa_off or (not ablation_gain and stem == r.ABLATION_ON):
            warm_k = 0
        img = _paint(target_dir, dims, warm_k=warm_k,
                     heavy=(snow == 'heavy'), pre=(phase == 'pre'))
        path = target_dir / png
        img.save(path)
        d = r.png_diag(str(path))
        want = r.expected_state(phase, snow, preset)
        if state_correct:
            st = dict(want)
            if qa_off:
                st['win_post'] = False
                st['win_pre'] = False
        else:
            st = {k: False for k in want}
        e = {
            'file': png, 'ok': True, 'preset': preset,
            'yaw_deg': yaw, 'pitch_deg': pitch, 'dist': dist,
            'c1_phase': phase, 'c1_snow': snow,
            'resolution': [dims[0], dims[1]], 'fog_mul': 0.12,
            'amb_state': st,
            'warm_frac': d['warm_frac'], 'lum_mean': d['lum_mean'],
            'white_frac': d['white_frac'], 'diag_samples': d['diag_samples'],
            'roofs_settled': True,
        }
        if include_focus:
            xyz = r.FOCI_XYZ[focus]
            cam = r.cam_formula(xyz, yaw, pitch, dist)
            e.update({
                'c1_focus': focus, 'focus_valid': True, 'focus_pick_ok': True,
                'focus_nav_closest_err': 0.02,
                'focus_nav_path_points': NAV_POINTS[focus],
                'focus_nav_path_end_err': 0.02,
                'focus_xyz': list(xyz), 'rig_target_xyz': list(xyz),
                'cam_xyz': list(cam), 'cam_xyz_formula': list(cam),
                'cam_actual_available': True,
            })
        if stem == r.ABLATION_ON:
            e['ablation'] = {'id': 'north_windows', 'arm': 'on',
                             'natural': True, 'pair': r.ABLATION_OFF + '.png'}
        elif stem == r.ABLATION_OFF:
            e['ablation'] = {'id': 'north_windows', 'arm': 'off',
                             'natural': False,
                             'override': 'qa_force_win_post_pre_off',
                             'pair': r.ABLATION_ON + '.png'}
        rkey = f'{focus}|{yaw:.0f}|{pitch:.0f}|{dist:.0f}'
        if rkey in first_ref:
            e['diff_vs_first_frac'] = _lum_diff_files(first_ref[rkey], path)
        else:
            first_ref[rkey] = path
        shots.append(e)
    man = {
        'kind': r.SHOTS_KIND, 'saved': len(shots), 'total': len(shots),
        'fog_mul': 0.12,
        'cam_bounds': {'pitch': [-80.0, -20.0], 'dist': [7.0, 26.0], 'fov': 42.0},
        'shots': shots,
    }
    (target_dir / 'shots_manifest.json').write_text(json.dumps(man), encoding='utf-8')


class C1RunnerTests(unittest.TestCase):
    def setUp(self):
        (ROOT / '.hermes').mkdir(exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix='c1-runner-unit-', dir=ROOT / '.hermes')
        self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name)

    def test_entrypoint_exists(self):
        self.assertTrue(SCRIPT.is_file(), 'C1 launcher must be in the repository')

    def test_matrix_constants(self):
        r = module()
        self.assertEqual(len(r.MATRIX), 24)
        self.assertEqual(set(r.FOCI_XYZ),
                         {'court', 'north_inner', 'south_w_inner', 'south_e_inner',
                          'west_inner', 'east_inner'})
        on = next(x for x in r.MATRIX if x[0] == r.ABLATION_ON)
        off = next(x for x in r.MATRIX if x[0] == r.ABLATION_OFF)
        self.assertTrue(off[8] and not on[8])
        # same focus/tags/rig for the ablation pair
        self.assertEqual(on[1:8], off[1:8])
        # C0 performance baseline rig unchanged (court/0/-54/17, small, noon)
        self.assertEqual(r.MATRIX[0][:8],
                         ('ps_noon_front', 'court', 'post', 'small', 'noon', 0.0, -54.0, 17.0))
        # every focus inside pick's rectangle |x|<10, -8<z<6.7
        for name, (x, _y, z) in r.FOCI_XYZ.items():
            self.assertTrue(abs(x) < 10 and -8 < z < 6.7, name)

    def test_expected_state_matches_projection(self):
        r = module()
        self.assertFalse(r.expected_state('post', 'small', 'noon')['win_post'])
        self.assertTrue(r.expected_state('post', 'small', 'night')['win_post'])
        self.assertTrue(r.expected_state('post', 'small', 'noon')['smoke_post'])
        self.assertTrue(r.expected_state('post', 'small', 'noon')['laundry'])
        self.assertFalse(r.expected_state('post', 'heavy', 'noon')['laundry'])
        self.assertTrue(r.expected_state('post', 'heavy', 'noon')['snow_heavy'])
        self.assertTrue(r.expected_state('post', 'small', 'noon')['damage'])
        self.assertFalse(r.expected_state('pre', 'small', 'noon')['damage'])
        self.assertTrue(r.expected_state('pre', 'small', 'noon')['smoke_pre'])
        self.assertFalse(r.expected_state('post', 'small', 'noon')['smoke_pre'])

    def test_valid_fixture_passes(self):
        r = module()
        d = self.base / 'ok720'
        write_fixture(d, (1280, 720))
        self.assertTrue(r.validate_c1_shots(str(d), (1280, 720)))

    def test_camera_formula_keeps_negative_pitch_above_ground(self):
        r = module()
        camera = r.cam_formula((2.0, 0.0, 3.0), 0.0, -30.0, 10.0)
        self.assertAlmostEqual(camera[1], 6.0, places=6)

    def test_actual_camera_and_target_cannot_be_forged(self):
        r = module()
        d = self.base / 'wrongcam'
        write_fixture(d, (1280, 720))
        path = d / 'shots_manifest.json'
        man = json.loads(path.read_text(encoding='utf-8'))
        man['shots'][0]['cam_xyz'] = [0.0, -100.0, 0.0]
        man['shots'][0]['rig_target_xyz'] = [99.0, 99.0, 99.0]
        path.write_text(json.dumps(man), encoding='utf-8')
        self.assertFalse(r.validate_c1_shots(str(d), (1280, 720)))

    def test_structure_failure_fails_contract_only_launcher(self):
        r = module()
        r.rebind_artifact_root(str(self.base / 'structure-launcher'))
        scenes = []
        def run_scene(name, args, timeout, cwd_logdir):
            scene = next(a for a in args if a.endswith('.tscn'))
            scenes.append(scene)
            structure = scene.endswith('courtyard_ambience_structure.tscn')
            code = 1 if structure else 0
            prefix = '[COURTYARD_AMB_STRUCTURE]' if structure else '[COURTYARD_AMBIENCE]'
            log = pathlib.Path(cwd_logdir) / (name + '.log')
            log.write_text(f'{prefix} COMPLETE code={code}\n', encoding='utf-8')
            return code, str(log), 0.0
        with patch.object(r.B, 'run', side_effect=run_scene), patch.object(sys, 'argv', ['runner', '--contract-only']):
            with self.assertRaises(SystemExit) as ended:
                r.main()
        self.assertEqual(ended.exception.code, 1)
        self.assertEqual(len(scenes), 2)

    def test_missing_manifest_rejected(self):
        r = module()
        self.assertFalse(r.validate_c1_shots(str(self.base / 'nope'), (1280, 720)))

    def test_wrong_recorded_state_rejected(self):
        r = module()
        d = self.base / 'badstate'
        write_fixture(d, (1280, 720), state_correct=False)
        self.assertFalse(r.validate_c1_shots(str(d), (1280, 720)))

    def test_gray_png_claiming_warm_rejected(self):
        # 磁盘复验红线：PNG 没有暖色，清单却报 warm_frac=0.9，必须拒绝。
        r = module()
        d = self.base / 'graylie'
        write_fixture(d, (1280, 720))
        _paint(d, (1280, 720), warm_k=0).save(d / 'ps_night_front.png')
        man_path = d / 'shots_manifest.json'
        man = json.loads(man_path.read_text(encoding='utf-8'))
        for s in man['shots']:
            if s['file'] == 'ps_night_front.png':
                s['warm_frac'] = 0.9
        man_path.write_text(json.dumps(man), encoding='utf-8')
        self.assertFalse(r.validate_c1_shots(str(d), (1280, 720)))

    def test_ablation_without_window_gain_rejected(self):
        # 消融两臂 PNG 相同（on 臂没有窗灯暖色）：gain=0，必须失败。
        r = module()
        d = self.base / 'nogain'
        write_fixture(d, (1280, 720), ablation_gain=False)
        self.assertFalse(r.validate_c1_shots(str(d), (1280, 720)))

    def test_qa_off_requires_honest_ablation_marker(self):
        # off 臂不得伪装成自然状态：去掉 ablation 标记并回填自然显隐必须失败。
        r = module()
        d = self.base / 'offmarker'
        write_fixture(d, (1280, 720))
        man_path = d / 'shots_manifest.json'
        man = json.loads(man_path.read_text(encoding='utf-8'))
        for s in man['shots']:
            if s['file'] == r.ABLATION_OFF + '.png':
                del s['ablation']
                s['amb_state'] = r.expected_state('post', 'small', 'night')
        man_path.write_text(json.dumps(man), encoding='utf-8')
        self.assertFalse(r.validate_c1_shots(str(d), (1280, 720)))

    def test_missing_focus_tags_rejected(self):
        r = module()
        d = self.base / 'nofocus'
        write_fixture(d, (1280, 720), include_focus=False)
        self.assertFalse(r.validate_c1_shots(str(d), (1280, 720)))

    def test_exit_marker_and_run_dir_escape_isolation(self):
        r = module()
        r.B.GODOT = sys.executable
        code, _, _ = r.B.run('unit-exit-seven', ['-c', 'raise SystemExit(7)'], 5, str(self.base))
        self.assertEqual(code, 7)
        # ROOT 重绑到隔离目录后，make_env 的所有路径必须严格落在 run_dir 内，
        # 不许 relpath 的 ../../ 越出（旧 wrapper 会落到 C0 工件根）。
        art = self.base / 'arte'
        run_dir = self.base / 'run1'
        r.rebind_artifact_root(str(art))
        env = r.B.make_env(str(run_dir))
        run_real = os.path.realpath(run_dir)
        for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME',
                    'XDG_CACHE_HOME', 'TMP', 'TEMP'):
            p = os.path.realpath(env[key])
            self.assertTrue(p.startswith(run_real + os.sep), f'{key}={p} 越出 {run_real}')
        env2 = r.B.make_env(str(self.base / 'run2'))
        for key in ('APPDATA', 'LOCALAPPDATA', 'TMP'):
            self.assertNotEqual(env[key], env2[key])

    def test_unique_run_directories(self):
        r = module()
        r.rebind_artifact_root(str(self.base / 'arte2'))
        a = pathlib.Path(r.B.new_run_dir('c1-after'))
        b = pathlib.Path(r.B.new_run_dir('c1-after'))
        self.assertNotEqual(a, b)
        self.assertTrue(a.is_dir() and b.is_dir())


if __name__ == '__main__':
    unittest.main()
