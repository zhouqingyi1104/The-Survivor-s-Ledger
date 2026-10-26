#!/usr/bin/env python
"""C0 scenery harness launcher — runs the Godot courtyard_scenery test with
fully isolated OS data dirs. Owns only the child processes it spawns.

Evidence integrity:
  * every invocation writes into a UNIQUE run dir (runs/<ts>_<phase>_<id>/),
    old evidence (including before/) is never deleted or overwritten;
  * --expect-red/--expect-green validates the contract exit code;
  * window runs are validated: completion marker, manifest saved/total/all-ok,
    every PNG exists with the requested pixel dimensions, perf trial/frame
    counts and resolution match the request;
  * any failure (nonzero child, timeout, missing marker, artifact mismatch)
    makes main() exit nonzero.

Parent callers may also import make_env/run/marker_ok/validate_shots/
validate_perf/new_run_dir and assert on the returned codes themselves.
"""
import json
import os
import struct
import subprocess
import sys
import time
import uuid

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT_EXE", os.path.join(PROJECT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe"))
ROOT = os.environ.get("COURTYARD_ARTIFACT_ROOT", os.path.join(PROJECT, ".hermes", "artifacts", "courtyard-scenery"))
SCENE = "res://tests/courtyard_scenery.tscn"
RULES_SCENE = "res://tests/courtyard_rules.tscn"
MARKER = "[COURTYARD_SCENERY] COMPLETE"

DIRS = {
    "APPDATA": ROOT + "/appdata/Roaming",
    "LOCALAPPDATA": ROOT + "/appdata/Local",
    "XDG_DATA_HOME": ROOT + "/xdg/data",
    "XDG_CONFIG_HOME": ROOT + "/xdg/config",
    "XDG_CACHE_HOME": ROOT + "/xdg/cache",
    "TMP": ROOT + "/tmp",
    "TEMP": ROOT + "/tmp",
}


def make_env(run_dir=None):
    env = os.environ.copy()
    for k, v in DIRS.items():
        if run_dir is not None:
            v = os.path.join(run_dir, "user-data", os.path.relpath(v, ROOT))
        os.makedirs(v, exist_ok=True)
        env[k] = v
    env["GODOT_DISABLE_VIDEO_SOUND"] = "1"  # no audio device needed
    return env


def run(name, args, timeout, cwd_logdir=ROOT):
    """Spawn one own child; return (code, log_path, seconds). Never masks
    timeouts or nonzero exits — timeout is reported as code 124."""
    log_path = os.path.join(cwd_logdir, name + ".log")
    print(f"=== {name}: {' '.join(args)}")
    t0 = time.time()
    with open(log_path, "wb") as logf:
        p = subprocess.Popen(
            [GODOT] + args,
            cwd=PROJECT,
            env=make_env(cwd_logdir),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        timed_out = False
        try:
            out, _ = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            p.kill()
            out, _ = p.communicate()
        logf.write(out)
    dt = time.time() - t0
    text = out.decode("utf-8", errors="replace")
    for line in text.splitlines():
        if "COURTYARD_SCENERY" in line or "SCRIPT ERROR" in line or "ERROR" in line:
            print("   ", line)
    code = 124 if timed_out else p.returncode
    if timed_out:
        print(f"!!! TIMEOUT after {timeout}s — killed own child pid {p.pid}")
    print(f"=== {name} exit={code} {dt:.1f}s log={log_path}")
    return code, log_path, dt


def marker_ok(log_path, expected_code=None):
    """The scene prints a final COMPLETE marker carrying its own exit code;
    a script aborted mid-function never reaches it, so printed counters alone
    cannot fake success."""
    with open(log_path, "rb") as f:
        lines = f.read().decode("utf-8", errors="replace").splitlines()
    markers = [ln for ln in lines if MARKER in ln]
    if not markers:
        print(f"!!! 缺少完成标记 {MARKER}：{log_path}")
        return False
    if expected_code is not None and f"code={expected_code}" not in markers[-1]:
        print(f"!!! 完成标记码不符（want {expected_code}）：{markers[-1].strip()}")
        return False
    return True


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def validate_shots(shots_dir, requested_wh, expect_total=16):
    man_path = os.path.join(shots_dir, "shots_manifest.json")
    if not os.path.isfile(man_path):
        print(f"!!! 截图清单不存在：{man_path}")
        return False
    try:
        with open(man_path, "r", encoding="utf-8") as f:
            man = json.load(f)
    except Exception as e:  # noqa: BLE001
        print(f"!!! 清单解析失败：{man_path}: {e}")
        return False
    shots = man.get("shots", [])
    ok = True
    if man.get("saved") != man.get("total") or man.get("total") != expect_total:
        print(f"!!! 清单计数不符 saved={man.get('saved')} total={man.get('total')} expect={expect_total}")
        ok = False
    if len(shots) != expect_total:
        print(f"!!! 清单条目数 {len(shots)} != {expect_total}")
        ok = False
    seen = set()
    for s in shots:
        fn = s.get("file", "")
        if fn in seen:
            print(f"!!! 清单重复条目：{fn}")
            ok = False
        seen.add(fn)
        if not s.get("ok"):
            print(f"!!! 清单条目标记失败：{fn}")
            ok = False
        p = os.path.join(shots_dir, fn)
        if not os.path.isfile(p):
            print(f"!!! PNG 缺失：{p}")
            ok = False
            continue
        dims = png_size(p)
        if dims is None:
            print(f"!!! 不是合法 PNG：{p}")
            ok = False
            continue
        if dims != tuple(requested_wh):
            print(f"!!! {fn} 实际像素 {dims} != 请求 {tuple(requested_wh)}")
            ok = False
        listed = tuple(s.get("resolution") or [0, 0])
        if listed != dims:
            print(f"!!! {fn} 清单登记 {listed} != 文件像素 {dims}")
            ok = False
    print(f"    shots 校验：{len(seen)}/{expect_total} PNG @ {tuple(requested_wh)} -> {'ok' if ok else 'FAIL'}")
    return ok


def validate_perf(perf_path, exp_trials, exp_frames, requested_wh):
    if not os.path.isfile(perf_path):
        print(f"!!! 性能 JSON 不存在：{perf_path}")
        return False
    try:
        with open(perf_path, "r", encoding="utf-8") as f:
            perf = json.load(f)
    except Exception as e:  # noqa: BLE001
        print(f"!!! 性能 JSON 解析失败：{perf_path}: {e}")
        return False
    ok = True
    trials = perf.get("trials", [])
    if len(trials) != exp_trials:
        print(f"!!! perf trials={len(trials)} != {exp_trials}")
        ok = False
    for i, t in enumerate(trials):
        if int(t.get("frames", 0)) != exp_frames:
            print(f"!!! perf trial {i} frames={t.get('frames')} != {exp_frames}")
            ok = False
        for key in ("frame_ms", "draw_calls", "objects_in_frame"):
            if key not in t or "median" not in t.get(key, {}):
                print(f"!!! perf trial {i} 缺少统计 {key}")
                ok = False
    if tuple(perf.get("resolution") or [0, 0]) != tuple(requested_wh):
        print(f"!!! perf 分辨率 {perf.get('resolution')} != {tuple(requested_wh)}")
        ok = False
    if str(perf.get("vsync_mode", "")) != "disabled":
        print(f"!!! perf vsync 实际未关闭：{perf.get('vsync_mode')}")
        ok = False
    med = [float(t["frame_ms"]["median"]) for t in trials if "frame_ms" in t]
    print("    perf 校验：%d trials x %d frames, median ms=%s -> %s" % (
        len(trials), exp_frames, ["%.3f" % m for m in med], "ok" if ok else "FAIL"))
    return ok


def new_run_dir(phase):
    rid = time.strftime("%Y%m%d-%H%M%S") + "_" + uuid.uuid4().hex[:6]
    d = os.path.join(ROOT, "runs", f"{rid}_{phase}")
    os.makedirs(d, exist_ok=False)
    return d


def _parse(argv):
    out = {"phase": "after", "expect": "green", "quick": False,
           "trials": 3, "samples": 240, "skip_1080": False, "contract_only": False}
    for a in argv:
        if a == "--quick":
            out["quick"] = True
        elif a == "--expect-red":
            out["expect"] = "red"
        elif a == "--expect-green":
            out["expect"] = "green"
        elif a == "--phase-before":
            out["phase"] = "before"
        elif a == "--phase-after":
            out["phase"] = "after"
        elif a == "--skip-1080":
            out["skip_1080"] = True
        elif a == "--contract-only":
            out["contract_only"] = True
        elif a.startswith("--trials="):
            out["trials"] = int(a.split("=", 1)[1])
        elif a.startswith("--samples="):
            out["samples"] = int(a.split("=", 1)[1])
    return out


def main():
    cfg = _parse(sys.argv[1:])
    label = cfg["phase"]
    run_dir = new_run_dir(label)
    print(f"=== run dir: {run_dir}")
    failures = []

    # 1) headless contract
    code, log, _ = run("contract_headless",
                       ["--headless", "--path", PROJECT, SCENE], 240, run_dir)
    want = 1 if cfg["expect"] == "red" else 0
    if code != want:
        failures.append(f"contract exit={code} want={want}")
    if code != 124 and not marker_ok(log, expected_code=code):
        failures.append("contract marker")

    if cfg["contract_only"]:
        print("SUMMARY failures=%s run=%s" % (failures, run_dir))
        sys.exit(1 if failures else 0)

    # 2) window capture 720 + perf
    shots_720 = os.path.join(run_dir, "shots_720").replace("\\", "/")
    perf_720 = os.path.join(run_dir, "perf_720.json").replace("\\", "/")
    args_720 = ["--path", PROJECT, SCENE, "--", "--baseline", "--label=" + label,
                "--shots=" + shots_720, "--perf=" + perf_720,
                "--resolution=1280x720", "--trials=%d" % cfg["trials"],
                "--samples=%d" % cfg["samples"]]
    if cfg["quick"]:
        args_720.append("--quick")
    code, log, _ = run("capture_720", args_720, 600, run_dir)
    if code != 0:
        failures.append(f"capture_720 exit={code}")
    else:
        if not marker_ok(log, expected_code=0):
            failures.append("capture_720 marker")
        if not validate_shots(shots_720, (1280, 720)):
            failures.append("shots_720")
        if not validate_perf(perf_720, cfg["trials"], cfg["samples"], (1280, 720)):
            failures.append("perf_720")

    # 3) window capture 1080 (no perf)
    if not cfg["skip_1080"]:
        shots_1080 = os.path.join(run_dir, "shots_1080").replace("\\", "/")
        args_1080 = ["--path", PROJECT, SCENE, "--", "--baseline", "--label=" + label,
                     "--shots=" + shots_1080, "--resolution=1920x1080", "--trials=1"]
        if cfg["quick"]:
            args_1080.append("--quick")
        code, log, _ = run("capture_1080", args_1080, 600, run_dir)
        if code != 0:
            failures.append(f"capture_1080 exit={code}")
        elif not marker_ok(log, expected_code=0) or not validate_shots(shots_1080, (1920, 1080)):
            failures.append("shots_1080")

    print("SUMMARY failures=%s run=%s" % (failures, run_dir))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()