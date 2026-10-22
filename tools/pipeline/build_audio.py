"""把下载的音效包和合成的声音挑出来、改名、统一转成 OGG，放进 assets/audio/。
同名多份的按 _1 _2 … 编号，游戏里随机挑一份放（audio.gd 的 VARIANTS 记着份数）。
用法：python -I build_audio.py <raw 目录> <合成目录> <输出目录>
需要 ffmpeg（libvorbis）。音效转单声道，音乐保留立体声。"""
import os, shutil, subprocess, sys

RAW, SYNTH, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
FFMPEG = shutil.which("ffmpeg") or "ffmpeg"

K_RPG = "kenney_rpg/Audio/"
K_IMP = "kenney_impact/Audio/"
K_UI = "kenney_interface/Audio/"


def seq(prefix, fmt, n, start=0):
    return [prefix + fmt % (start + i) for i in range(n)]


# 输出名 → 来源（相对 RAW；以 "synth:" 开头的来自合成目录）
SFX = {
    # 界面
    "ui_click": [K_UI + "click_002.ogg", K_UI + "click_003.ogg"],
    "ui_open": [K_UI + "open_002.ogg"],
    "ui_close": [K_UI + "close_002.ogg"],
    "ui_error": [K_UI + "error_006.ogg"],
    "ui_confirm": [K_UI + "confirmation_002.ogg"],
    "ui_tick": [K_UI + "tick_002.ogg"],
    # 物件
    "coins": [K_RPG + "handleCoins.ogg", K_RPG + "handleCoins2.ogg"],
    "book": seq(K_RPG + "bookFlip", "%d.ogg", 3, 1),
    "book_place": seq(K_RPG + "bookPlace", "%d.ogg", 3, 1),
    "door_open": seq(K_RPG + "doorOpen_", "%d.ogg", 2, 1),
    "door_close": seq(K_RPG + "doorClose_", "%d.ogg", 4, 1),
    "creak": seq(K_RPG + "creak", "%d.ogg", 3, 1),
    "pot": seq(K_RPG + "metalPot", "%d.ogg", 3, 1),
    "knife": [K_RPG + "knifeSlice.ogg", K_RPG + "knifeSlice2.ogg"],
    "chop": [K_RPG + "chop.ogg"],
    "cloth": seq(K_RPG + "cloth", "%d.ogg", 4, 1),
    "leather": [K_RPG + "dropLeather.ogg", K_RPG + "handleSmallLeather.ogg", K_RPG + "handleSmallLeather2.ogg"],
    "latch": [K_RPG + "metalLatch.ogg"],
    # 脚步
    "step_snow": seq(K_IMP + "footstep_snow_", "%03d.ogg", 5),
    "step_stone": seq(K_IMP + "footstep_concrete_", "%03d.ogg", 5),
    "step_wood": seq(K_IMP + "footstep_wood_", "%03d.ogg", 5),
    # 撞击
    "hit_door": seq(K_IMP + "impactWood_heavy_", "%03d.ogg", 5),
    "hammer": seq(K_IMP + "impactWood_medium_", "%03d.ogg", 5),
    "hit_plank": seq(K_IMP + "impactPlank_medium_", "%03d.ogg", 5),
    "hit_soft": seq(K_IMP + "impactSoft_heavy_", "%03d.ogg", 5),
    "dig": seq(K_IMP + "impactSoft_medium_", "%03d.ogg", 5),
    "punch": seq(K_IMP + "impactPunch_heavy_", "%03d.ogg", 5),
    "bell": seq(K_IMP + "impactBell_heavy_", "%03d.ogg", 5),
    # 僵尸、风
    "zombie": ["oga_zombies/zombies/zombie-%d.wav" % i for i in range(1, 25)],
    "gust": ["oga_wind/wind/Wind.ogg", "oga_wind/wind/Wind2.ogg", "oga_wind/wind/Wind3.ogg"],
    # 合成
    "bangzi": ["synth:bangzi.wav"],
    "genggu": ["synth:genggu.wav"],
    "ling": ["synth:ling.wav"],
    "luo": ["synth:luo.wav"],
    "water_draw": ["synth:water_draw.wav"],
    "sip": ["synth:sip.wav"],
}
AMB = {
    "wind_loop": "synth:wind_loop.wav",
    "fire_loop": "../oga_fire/fire.wav",
}
MUSIC = {
    "lotus_pond": "biteme_chinese_music/Lotus Pond - Loop.wav",
    "dragon_dance": "biteme_chinese_music/Dragon Dance - Loop.wav",
}


def src_path(s):
    return os.path.join(SYNTH, s[6:]) if s.startswith("synth:") else os.path.join(RAW, s)


def convert(src, dest, mono=True, quality=4):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    cmd = [FFMPEG, "-y", "-loglevel", "error", "-i", src]
    if mono:
        cmd += ["-ac", "1"]
    cmd += ["-ar", "44100", "-c:a", "libvorbis", "-q:a", str(quality), dest]
    subprocess.run(cmd, check=True)


counts = {}
for name, sources in SFX.items():
    for i, s in enumerate(sources):
        dest = os.path.join(OUT, "sfx", name + ("_%d" % (i + 1) if len(sources) > 1 else "") + ".ogg")
        convert(src_path(s), dest)
    counts[name] = len(sources)
for name, s in AMB.items():
    convert(src_path(s), os.path.join(OUT, "amb", name + ".ogg"))
for name, s in MUSIC.items():
    convert(src_path(s), os.path.join(OUT, "music", name + ".ogg"), mono=False, quality=5)
print("VARIANTS =", counts)
total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(OUT) for f in fs if f.endswith(".ogg"))
print("total %.1f MB" % (total / 1e6))
