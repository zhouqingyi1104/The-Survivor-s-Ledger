#!/usr/bin/env python
"""C1 home-ambience harness launcher — thin wrapper over the C0 launcher.

Runs res://tests/courtyard_ambience.tscn with the same OS-level isolation,
unique run dirs, completion-marker gating, PNG/perf validation as C0, plus C1
evidence checks:

  * 24-shot matrix over SIX genuinely reachable in-courtyard foci (court,
    north_inner, south_w_inner, south_e_inner, west_inner, east_inner).
    Reachability is not a name allow-list: the Godot side re-checks every focus
    against HomeWorld.pick's ground rectangle AND a real NavigationServer3D
    path/closest-point query (XZ error < .15); the manifest fields are gated
    here as well.
  * every entry records the REAL 8-group ambience .visible vector (read from
    nodes, not the cache meta) and real in-engine pixel diagnostics;
  * the diagnostics are RE-COMPUTED FROM THE PNG BYTES HERE (Pillow, same
    step-4 sampling as the GDScript): a gray PNG with a warm_frac in the
    manifest is rejected outright;
  * the north night window on/off ablation is same-rig/same-preset and its
    warm pixel gain + changed pixels are recomputed from disk (>=10 px). The
    OFF arm is an explicit QA light override, tagged natural=false — never a
    claimed world state;
  * whole-frame diffs for heavy/pre are recorded for human inspection only
    (no view-dependent numeric gate); structural contracts + ablation + the
    parent's visual acceptance are the judges.

No game captures are fabricated: every number comes from a Godot run and is
re-validated from the PNGs/manifest on disk. Pillow is a hard dependency of
this checker; if it is missing the run fails loudly instead of going green.
"""
import importlib.util
import json
import math
import os
import pathlib
import sys

_HERE = pathlib.Path(__file__).resolve().parent
_BASE_PATH = _HERE / "test_courtyard_scenery.py"


def _base():
    spec = importlib.util.spec_from_file_location("c0_scenery_launcher", _BASE_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


B = _base()

SCENE = "res://tests/courtyard_ambience.tscn"
STRUCTURE_SCENE = "res://tests/courtyard_ambience_structure.tscn"
EXPECT_TOTAL = 24
SHOTS_KIND = "courtyard_c1_ambience_shots"
PERF_KIND = "courtyard_c1_ambience_perf"
NIGHT_LIKE = ("dusk", "night", "blood")
NAV_TOL = 0.15
WARM_GAIN_MIN = 10  # conservative ablation threshold, recomputed from PNG bytes

# Six legal foci. XYZ must match C1_FOCI in tests/courtyard_ambience.gd; every
# one is inside HomeWorld.pick's rectangle (|x|<10, -8<z<GATE_Z-0.3=6.7) and on
# the baked nav mesh (verified at runtime).
FOCI_XYZ = {
    "court": (0.0, 0.0, 0.0),
    "north_inner": (-0.8, 0.0, -5.5),
    "south_w_inner": (-6.2, 0.0, 6.0),
    "south_e_inner": (6.2, 0.0, 6.0),
    "west_inner": (-8.0, 0.0, 4.5),
    "east_inner": (8.0, 0.0, 4.5),
}

# Single source of truth for the expected 24-shot matrix (tags + rig).
# qa_win_off=True marks the explicit QA window-light ablation arm.
MATRIX = [
    ("ps_noon_front", "court", "post", "small", "noon", 0.0, -54.0, 17.0, False),
    ("ps_noon_back", "court", "post", "small", "noon", 180.0, -54.0, 17.0, False),
    ("ps_noon_left", "court", "post", "small", "noon", -90.0, -54.0, 17.0, False),
    ("ps_noon_right", "court", "post", "small", "noon", 90.0, -54.0, 17.0, False),
    ("ps_night_front", "court", "post", "small", "night", 0.0, -54.0, 17.0, False),
    ("ps_noon_south_w", "south_w_inner", "post", "small", "noon", 180.0, -40.0, 26.0, False),
    ("ps_noon_south_e", "south_e_inner", "post", "small", "noon", 180.0, -40.0, 26.0, False),
    ("ps_noon_north", "north_inner", "post", "small", "noon", 0.0, -50.0, 26.0, False),
    ("ps_dusk_north", "north_inner", "post", "small", "dusk", 0.0, -50.0, 26.0, False),
    ("ps_night_north_on", "north_inner", "post", "small", "night", 0.0, -50.0, 26.0, False),
    ("ps_night_north_off", "north_inner", "post", "small", "night", 0.0, -50.0, 26.0, True),
    ("ps_noon_west", "west_inner", "post", "small", "noon", 90.0, -40.0, 26.0, False),
    ("ps_noon_east", "east_inner", "post", "small", "noon", -90.0, -40.0, 26.0, False),
    ("ps_low_south_e", "south_e_inner", "post", "small", "noon", 180.0, -20.0, 26.0, False),
    ("ps_low_north", "north_inner", "post", "small", "noon", 0.0, -20.0, 26.0, False),
    ("ph_noon_south_w", "south_w_inner", "post", "heavy", "noon", 180.0, -40.0, 26.0, False),
    ("ph_noon_south_e", "south_e_inner", "post", "heavy", "noon", 180.0, -40.0, 26.0, False),
    ("ph_noon_north", "north_inner", "post", "heavy", "noon", 0.0, -50.0, 26.0, False),
    ("ph_noon_court", "court", "post", "heavy", "noon", 0.0, -54.0, 17.0, False),
    ("ph_night_court", "court", "post", "heavy", "night", 0.0, -54.0, 17.0, False),
    ("ph_blood_north", "north_inner", "post", "heavy", "blood", 0.0, -50.0, 26.0, False),
    ("pre_noon_south_w", "south_w_inner", "pre", "small", "noon", 180.0, -40.0, 26.0, False),
    ("pre_noon_north", "north_inner", "pre", "small", "noon", 0.0, -50.0, 26.0, False),
    ("pre_night_north", "north_inner", "pre", "small", "night", 0.0, -50.0, 26.0, False),
]
MATRIX_BY_FILE = {row[0]: row for row in MATRIX}
ABLATION_ON = "ps_night_north_on"
ABLATION_OFF = "ps_night_north_off"


def rebind_artifact_root(root):
    """Point the C0 helpers at C1's artifact root WITHOUT escaping run dirs.

    Import-time DIRS still point at the C0 root; os.path.relpath across roots
    would produce ../../ escapes, so rebuild DIRS from explicit clean
    relative subpaths under the new root.
    """
    B.ROOT = str(root)
    B.DIRS = {
        "APPDATA": os.path.join(B.ROOT, "appdata", "Roaming"),
        "LOCALAPPDATA": os.path.join(B.ROOT, "appdata", "Local"),
        "XDG_DATA_HOME": os.path.join(B.ROOT, "xdg", "data"),
        "XDG_CONFIG_HOME": os.path.join(B.ROOT, "xdg", "config"),
        "XDG_CACHE_HOME": os.path.join(B.ROOT, "xdg", "cache"),
        "TMP": os.path.join(B.ROOT, "tmp"),
        "TEMP": os.path.join(B.ROOT, "tmp"),
    }


rebind_artifact_root(os.environ.get(
    "COURTYARD_ARTIFACT_ROOT",
    os.path.join(B.PROJECT, ".hermes", "artifacts", "courtyard-ambience"),
))
B.SCENE = SCENE


def expected_state(phase, snow, preset):
    """Mirror of HomeAmbience.project for the preset clocks used by the matrix."""
    night = preset in NIGHT_LIKE  # dusk=18:00, night/blood=23:00 -> night band
    heavy = snow == "heavy"
    pre = phase == "pre"
    return {
        "win_post": night,
        "win_pre": night and pre,
        "smoke_post": not night,
        "smoke_pre": (not night) and pre,
        "laundry": (not night) and not heavy,
        "traces": not heavy,
        "damage": not pre,
        "snow_heavy": heavy,
    }


def cam_formula(focus_xyz, yaw_deg, pitch_deg, dist):
    """Mirrors CamRig: focus+(0,1,0) + (0,0,d).rotated(X,pitch).rotated(Y,yaw)."""
    fx, fy, fz = focus_xyz
    pr = math.radians(pitch_deg)
    yr = math.radians(yaw_deg)
    x0, y0, z0 = 0.0, -math.sin(pr) * dist, math.cos(pr) * dist
    x1 = x0 * math.cos(yr) + z0 * math.sin(yr)
    z1 = -x0 * math.sin(yr) + z0 * math.cos(yr)
    return (fx + x1, fy + 1.0 + y0, fz + z1)


# ---------- PNG byte re-verification (same step-4 sampling as the GDScript) ----------

def png_diag(path):
    """Recompute warm/lum/white/sample_count from a PNG on disk.

    Uses the exact predicate of courtyard_ambience.gd::_image_diag. ImportError
    propagates on purpose so callers fail loudly, never green.
    """
    from PIL import Image
    img = Image.open(path)
    img.load()
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    px = img.load()
    warm = white = n = 0
    lum_sum = 0.0
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            r, g, b = px[x, y][:3]
            lum_sum += (0.3 * r + 0.59 * g + 0.11 * b) / 255.0
            if r > 110 and r - b > 45 and r - g > 15:
                warm += 1
            if r > 200 and g > 200 and b > 200:
                white += 1
            n += 1
    return {"warm_frac": warm / n, "lum_mean": lum_sum / n,
            "white_frac": white / n, "diag_samples": n,
            "_warm_px": warm, "_white_px": white, "_size": (w, h)}


def png_ablation_gain(on_path, off_path):
    """Warm pixel delta + raw changed pixels between two same-rig PNGs."""
    from PIL import Image
    a = Image.open(on_path).convert("RGB")
    b = Image.open(off_path).convert("RGB")
    if a.size != b.size:
        return None
    pa, pb = a.load(), b.load()
    warm_gain = changed = 0
    for y in range(0, a.size[1], 4):
        for x in range(0, a.size[0], 4):
            ra, ga, ba = pa[x, y][:3]
            rb, gb, bb = pb[x, y][:3]
            wa = ra > 110 and ra - ba > 45 and ra - ga > 15
            wb = rb > 110 and rb - bb > 45 and rb - gb > 15
            if wa and not wb:
                warm_gain += 1
            if abs(ra - rb) + abs(ga - gb) + abs(ba - bb) > 24:
                changed += 1
    return {"warm_gain_px": warm_gain, "changed_px": changed}


def validate_c1_shots(shots_dir, requested_wh):
    if not B.validate_shots(shots_dir, requested_wh, expect_total=EXPECT_TOTAL):
        return False
    man_path = os.path.join(shots_dir, "shots_manifest.json")
    with open(man_path, "r", encoding="utf-8") as f:
        man = json.load(f)
    ok = True
    if man.get("kind") != SHOTS_KIND:
        print(f"!!! manifest kind={man.get('kind')} != {SHOTS_KIND}")
        ok = False
    bounds = man.get("cam_bounds") or {}
    if bounds != {"pitch": [-80.0, -20.0], "dist": [7.0, 26.0], "fov": 42.0}:
        print(f"!!! cam_bounds 被改动：{bounds}")
        ok = False
    if abs(float(man.get("fog_mul", 0.0)) - 0.12) > 0.001:
        print(f"!!! fog_mul={man.get('fog_mul')}（须保持 0.12）")
        ok = False

    try:
        diags = {s.get("file"): png_diag(os.path.join(shots_dir, s.get("file", "")))
                 for s in man.get("shots", [])}
    except ImportError as e:
        print(f"!!! PNG 磁盘复验依赖缺失，拒绝假绿：{e}")
        return False
    except Exception as e:  # noqa: BLE001
        print(f"!!! PNG 磁盘复验无法执行：{e}")
        return False

    shots = man.get("shots", [])
    want_files = {row[0] + ".png" for row in MATRIX}
    files_seen = {s.get("file", "") for s in shots}
    if files_seen != want_files:
        print(f"!!! 矩阵文件集合不符；缺 {sorted(want_files - files_seen)[:5]}，"
              f"多 {sorted(files_seen - want_files)[:5]}")
        ok = False

    foci_seen = set()
    signatures = set()
    for s in shots:
        fn = s.get("file", "")
        stem = fn[:-4] if fn.endswith(".png") else fn
        row = MATRIX_BY_FILE.get(stem)
        if row is None:
            print(f"!!! 清单条目不在矩阵中：{fn}")
            ok = False
            continue
        _, focus, phase, snow, preset, yaw, pitch, dist, qa_off = row
        tags = (phase, snow, preset)
        if (s.get("c1_phase"), s.get("c1_snow"), s.get("preset")) != tags:
            print(f"!!! {fn} 标签不符：{s.get('c1_phase')}/{s.get('c1_snow')}/{s.get('preset')}")
            ok = False
        for key, want in (("yaw_deg", yaw), ("pitch_deg", pitch), ("dist", dist)):
            if abs(float(s.get(key, -999.0)) - want) > 0.01:
                print(f"!!! {fn} {key}={s.get(key)} != {want}")
                ok = False
        if abs(float(s.get("fog_mul", 0.0)) - 0.12) > 0.001:
            print(f"!!! {fn} fog_mul={s.get('fog_mul')}（须 0.12）")
            ok = False
        # 焦点合法性：名字 + 坐标 + 真实 pick/导航字段，全部门控，不靠名单。
        xyz = s.get("focus_xyz")
        if s.get("c1_focus") != focus or not isinstance(xyz, list) or len(xyz) != 3 \
                or any(abs(float(xyz[i]) - FOCI_XYZ[focus][i]) > 0.03 for i in range(3)):
            print(f"!!! {fn} 焦点名/坐标不符：{s.get('c1_focus')} {xyz}")
            ok = False
        foci_seen.add(s.get("c1_focus"))
        if not s.get("focus_valid") or not s.get("focus_pick_ok"):
            print(f"!!! {fn} focus_valid/pick_ok 非真：{s.get('focus_valid')}/{s.get('focus_pick_ok')}")
            ok = False
        for key in ("focus_nav_closest_err", "focus_nav_path_end_err"):
            v = s.get(key)
            if not isinstance(v, (int, float)) or not (0.0 <= float(v) < NAV_TOL):
                print(f"!!! {fn} {key}={v}（须 [0,{NAV_TOL})）")
                ok = False
        if not isinstance(s.get("focus_nav_path_points"), int) or s["focus_nav_path_points"] < 2:
            print(f"!!! {fn} 真实导航路径点数={s.get('focus_nav_path_points')}（须>=2）")
            ok = False
        want_cam = cam_formula(FOCI_XYZ[focus], yaw, pitch, dist)
        for key, want_xyz in (("rig_target_xyz", FOCI_XYZ[focus]),
                              ("cam_xyz", want_cam), ("cam_xyz_formula", want_cam)):
            v = s.get(key)
            if not isinstance(v, list) or len(v) != 3 or not all(
                    type(c) in (int, float) and math.isfinite(c) for c in v):
                print(f"!!! {fn} 缺真实机位记录 {key}：{v}")
                ok = False
            elif any(abs(v[i] - want_xyz[i]) > 0.04 for i in range(3)):
                print(f"!!! {fn} 真实机位 {key}={v} != {want_xyz}")
                ok = False
        if s.get("cam_actual_available") is not True or s.get("roofs_settled") is not True:
            print(f"!!! {fn} 缺真实相机或屋顶未稳定")
            ok = False
        # 真实 8 组显隐：自然臂等于投影；QA off 只允许窗灯两键被显式覆盖。
        st = s.get("amb_state")
        want_st = expected_state(*tags)
        abl = s.get("ablation")
        if qa_off:
            want_off = dict(want_st)
            want_off["win_post"] = False
            want_off["win_pre"] = False
            if st != want_off:
                print(f"!!! {fn} QA off amb_state={st} 与显式关灯期望 {want_off} 不符")
                ok = False
            if not (isinstance(abl, dict) and abl.get("arm") == "off"
                    and abl.get("natural") is False and abl.get("override")):
                print(f"!!! {fn} QA 关灯臂必须带诚实 ablation 标记：{abl}")
                ok = False
        else:
            if st != want_st:
                print(f"!!! {fn} amb_state={st} 与标签期望 {want_st} 不符")
                ok = False
            if stem == ABLATION_ON and not (
                    isinstance(abl, dict) and abl.get("arm") == "on" and abl.get("natural") is True):
                print(f"!!! {fn} 消融 on 臂须带 natural=true 标记：{abl}")
                ok = False
        if isinstance(st, dict):
            signatures.add(tuple(sorted(st.items())))
        # 磁盘像素复验：manifest 数字必须能从 PNG 重算出来。
        d = diags.get(fn)
        if d is None:
            ok = False
            continue
        if d["diag_samples"] != s.get("diag_samples"):
            print(f"!!! {fn} diag_samples 清单 {s.get('diag_samples')} != PNG {d['diag_samples']}")
            ok = False
        man_warm = round(float(s.get("warm_frac", -1.0)) * d["diag_samples"])
        man_white = round(float(s.get("white_frac", -1.0)) * d["diag_samples"])
        if abs(man_warm - d["_warm_px"]) > 8:
            print(f"!!! {fn} warm 像素 清单={man_warm} PNG实算={d['_warm_px']}（暖色证据造假或统计不符）")
            ok = False
        if abs(man_white - d["_white_px"]) > 8:
            print(f"!!! {fn} white 像素 清单={man_white} PNG实算={d['_white_px']}")
            ok = False
        if abs(float(s.get("lum_mean", -1.0)) - d["lum_mean"]) > 0.006:
            print(f"!!! {fn} lum_mean 清单={s.get('lum_mean')} PNG实算={d['lum_mean']:.5f}")
            ok = False

    if foci_seen != set(FOCI_XYZ):
        print(f"!!! 六焦点覆盖不全：{sorted(f for f in foci_seen if f)}（须 {sorted(FOCI_XYZ)}）")
        ok = False
    if len(signatures) < 6:
        print(f"!!! 24 机位只出现 {len(signatures)} 种小组显隐组合（期望 >=6）")
        ok = False

    # 同机位窗灯 on/off 消融：增益与像素差一律从磁盘 PNG 实算。
    gain = png_ablation_gain(
        os.path.join(shots_dir, ABLATION_ON + ".png"),
        os.path.join(shots_dir, ABLATION_OFF + ".png"))
    if gain is None:
        print("!!! 消融对 PNG 尺寸不一致")
        ok = False
    else:
        print(f"    消融 north on/off：warm_gain={gain['warm_gain_px']}px "
              f"changed={gain['changed_px']}px（阈值均 >={WARM_GAIN_MIN}）")
        if gain["warm_gain_px"] < WARM_GAIN_MIN or gain["changed_px"] < WARM_GAIN_MIN:
            print("!!! 同机位夜窗 on/off 无可测窗灯增益（不能证明暖光来自邻宅窗灯）")
            ok = False

    # whole-frame 差异只如实记录，不做视角依赖阈值门控（结构契约+消融+父目视判据）。
    for s in shots:
        d = s.get("diff_vs_first_frac")
        if isinstance(d, (int, float)):
            print(f"    {s.get('file')} diff_vs_first={d:.4f}（记录值，人工/结构判据）")
    return ok


def _parse(argv):
    cfg = {"expect": "green", "quick": False, "trials": 3, "samples": 240,
           "skip_1080": False, "contract_only": False}
    for a in argv:
        if a == "--quick":
            cfg["quick"] = True
        elif a == "--expect-red":
            cfg["expect"] = "red"
        elif a == "--expect-green":
            cfg["expect"] = "green"
        elif a == "--skip-1080":
            cfg["skip_1080"] = True
        elif a == "--contract-only":
            cfg["contract_only"] = True
        elif a.startswith("--trials="):
            cfg["trials"] = int(a.split("=", 1)[1])
        elif a.startswith("--samples="):
            cfg["samples"] = int(a.split("=", 1)[1])
    return cfg


def main():
    cfg = _parse(sys.argv[1:])
    label = "after"
    run_dir = B.new_run_dir("c1-" + label)
    print(f"=== C1 run dir: {run_dir}")
    failures = []

    def marker_ok(path, code, prefix="[COURTYARD_AMBIENCE]"):
        # C1 子类覆盖 _finish，打印的是 [COURTYARD_AMBIENCE] 完成标记。
        with open(path, "rb") as f:
            lines = f.read().decode("utf-8", errors="replace").splitlines()
        markers = [ln for ln in lines if prefix + " COMPLETE" in ln]
        if not markers or f"code={code}" not in markers[-1]:
            print(f"!!! C1 完成标记缺失/码不符：{markers[-1:] or ['<none>']}")
            return False
        return True

    code, log, _ = B.run("contract_headless",
                         ["--headless", "--path", B.PROJECT, SCENE], 240, run_dir)
    want = 1 if cfg["expect"] == "red" else 0
    if code != want:
        failures.append(f"contract exit={code} want={want}")
    if code != 124 and not marker_ok(log, code):
        failures.append("contract marker")

    # 永久烟囱/晾衣支架与活动烟衣必须一起验；不能默认漏跑结构契约。
    structure_code, structure_log, _ = B.run("contract_structure",
        ["--headless", "--path", B.PROJECT, STRUCTURE_SCENE], 120, run_dir)
    if structure_code != 0:
        failures.append(f"structure exit={structure_code}")
    if structure_code != 124 and not marker_ok(structure_log, structure_code, "[COURTYARD_AMB_STRUCTURE]"):
        failures.append("structure marker")

    if cfg["contract_only"]:
        print("C1 SUMMARY failures=%s run=%s" % (failures, run_dir))
        sys.exit(1 if failures else 0)

    shots_720 = os.path.join(run_dir, "shots_720").replace("\\", "/")
    perf_720 = os.path.join(run_dir, "perf_720.json").replace("\\", "/")
    args_720 = ["--path", B.PROJECT, SCENE, "--", "--baseline", "--label=" + label,
                "--shots=" + shots_720, "--perf=" + perf_720,
                "--resolution=1280x720", "--trials=%d" % cfg["trials"],
                "--samples=%d" % cfg["samples"]]
    if cfg["quick"]:
        args_720.append("--quick")
    code, log, _ = B.run("capture_720", args_720, 900, run_dir)
    if code != 0:
        failures.append(f"capture_720 exit={code}")
    else:
        if not marker_ok(log, 0):
            failures.append("capture_720 marker")
        if not validate_c1_shots(shots_720, (1280, 720)):
            failures.append("shots_720")
        if not B.validate_perf(perf_720, cfg["trials"], cfg["samples"], (1280, 720)):
            failures.append("perf_720")
        else:
            with open(perf_720, "r", encoding="utf-8") as f:
                perf = json.load(f)
            if perf.get("kind") != PERF_KIND:
                print(f"!!! perf kind={perf.get('kind')} != {PERF_KIND}")
                failures.append("perf_720 kind")

    if not cfg["skip_1080"]:
        shots_1080 = os.path.join(run_dir, "shots_1080").replace("\\", "/")
        args_1080 = ["--path", B.PROJECT, SCENE, "--", "--baseline", "--label=" + label,
                     "--shots=" + shots_1080, "--resolution=1920x1080", "--trials=1"]
        if cfg["quick"]:
            args_1080.append("--quick")
        code, log, _ = B.run("capture_1080", args_1080, 900, run_dir)
        if code != 0:
            failures.append(f"capture_1080 exit={code}")
        elif not marker_ok(log, 0) or not validate_c1_shots(
                shots_1080, (1920, 1080)):
            failures.append("shots_1080")

    print("C1 SUMMARY failures=%s run=%s" % (failures, run_dir))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
