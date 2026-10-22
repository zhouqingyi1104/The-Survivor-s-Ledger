"""合成素材包里没有的中式声音：梆子、更鼓、赶尸铃、铜锣、风雪（可无缝循环）、打水。
纯程序生成（加性合成 + 滤波噪声），没有采样，版权归本项目。
用法：python -I synth_sfx.py <输出目录>   输出 44.1 kHz 16 位单声道 WAV。"""
import os, sys
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

SR = 44100
OUT = sys.argv[1]
rng = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def low(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def high(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


def partials(t, f0, ratios, decays, amps, detune=0.0):
    y = np.zeros_like(t)
    for r, d, a in zip(ratios, decays, amps):
        f = f0 * r * (1.0 + rng.uniform(-detune, detune))
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t / d)
    return y


def norm(x, peak=0.89):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def fade(x, a=0.002, b=0.05):
    n_a, n_b = int(a * SR), int(b * SR)
    x = x.copy()
    if n_a:
        x[:n_a] *= np.linspace(0, 1, n_a)
    if n_b:
        x[-n_b:] *= np.linspace(1, 0, n_b)
    return x


def save(name, x, peak=0.89):
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (norm(x, peak) * 32767).astype(np.int16))
    print(name, "%.2fs" % (len(x) / SR))


# 梆子：硬木空腔，一声清脆的"梆"——两个高频共振峰，衰减极快，加一下木头的咔嗒
def bangzi():
    t = t_axis(0.35)
    body = partials(t, 1180, [1.0, 2.43, 3.9], [0.045, 0.022, 0.012], [1.0, 0.45, 0.18])
    click = high(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.003) * 0.6
    knock = band(rng.standard_normal(len(t)), 700, 1800) * np.exp(-t / 0.012) * 0.5
    return fade(body + click + knock, 0.0005, 0.08)


# 更鼓：皮面大鼓，音高从高往低滑，带一下闷响
def genggu():
    t = t_axis(1.4)
    f = 68 + 55 * np.exp(-t / 0.06)
    phase = 2 * np.pi * np.cumsum(f) / SR
    fund = np.sin(phase) * np.exp(-t / 0.38)
    over = np.sin(phase * 1.59 + 0.7) * np.exp(-t / 0.12) * 0.35 + np.sin(phase * 2.14) * np.exp(-t / 0.07) * 0.2
    thump = low(rng.standard_normal(len(t)), 400) * np.exp(-t / 0.02) * 1.6
    skin = band(rng.standard_normal(len(t)), 900, 3000) * np.exp(-t / 0.008) * 0.25
    return fade(fund + over + thump + skin, 0.001, 0.2)


# 赶尸铃：摇一下小铜铃，叮叮叮三下，余音带拍频
def ling():
    t = t_axis(2.6)
    y = np.zeros_like(t)
    for k, (start, amp) in enumerate([(0.0, 1.0), (0.13, 0.8), (0.27, 0.9), (0.52, 0.55)]):
        n0 = int(start * SR)
        tt = t[: len(t) - n0]
        s = partials(tt, 1630 + k * 6, [1.0, 2.32, 4.25, 6.63, 9.4], [1.1, 0.6, 0.35, 0.2, 0.1], [1.0, 0.6, 0.35, 0.2, 0.1], 0.004)
        s += partials(tt, 1637 + k * 6, [1.0, 2.32], [1.0, 0.5], [0.5, 0.25])
        s += high(rng.standard_normal(len(tt)), 4000) * np.exp(-tt / 0.002) * 0.3
        y[n0:] += amp * s
    return fade(y, 0.0005, 0.4)


# 铜锣：尸潮来了的报警——一声开锣，低频的嗡鸣慢慢起来，音高微微下滑
def luo():
    t = t_axis(4.2)
    y = np.zeros_like(t)
    f0 = 210.0
    ratios = [1.0, 1.52, 2.03, 2.47, 2.91, 3.6, 4.33, 5.1, 6.2, 7.4]
    for i, r in enumerate(ratios):
        bend = 1.0 - 0.035 * (1 - np.exp(-t / 0.6))
        phase = 2 * np.pi * np.cumsum(f0 * r * bend) / SR + rng.uniform(0, 6.28)
        swell = 1.0 - np.exp(-t / (0.02 + 0.05 * i))
        y += (0.9 ** i) * np.sin(phase) * swell * np.exp(-t / (2.2 - 0.15 * i))
    hit = band(rng.standard_normal(len(t)), 300, 2500) * np.exp(-t / 0.03) * 0.8
    return fade(y + hit, 0.001, 0.8)


# 风雪：低沉的风声，忽强忽弱，偶尔一阵呼哨。前后交叉淡化，可以无缝循环
def wind_loop():
    sec, xf = 24.0, 3.0
    t = t_axis(sec + xf)
    brown = np.cumsum(rng.standard_normal(len(t)))
    brown = high(brown, 20)
    brown /= np.max(np.abs(brown))
    gust = 0.66 + 0.21 * np.sin(2 * np.pi * 0.11 * t + 1.0) + 0.13 * np.sin(2 * np.pi * 0.047 * t)
    body = low(band(brown, 60, 900), 700) * gust
    white = rng.standard_normal(len(t))
    whistle = band(white, 520, 760, 3) * np.clip(np.sin(2 * np.pi * 0.06 * t - 0.5), 0, 1) ** 2 * 0.25
    hiss = band(white, 2500, 7000) * 0.025 * gust
    y = body + whistle + hiss
    n, nx = int(sec * SR), int(xf * SR)
    head, tail = y[:nx], y[n:n + nx]
    ramp = np.linspace(0, 1, nx)
    out = y[:n].copy()
    out[:nx] = head * ramp + tail * (1 - ramp)
    return out


# 打水：木桶落水"扑通"，咕嘟冒泡，再哗啦倒进水缸
def water_draw():
    t = t_axis(2.2)
    y = np.zeros_like(t)
    # 落水
    n0 = int(0.05 * SR)
    tt = t[: len(t) - n0]
    plunge = band(rng.standard_normal(len(tt)), 250, 3500) * np.exp(-tt / 0.07)
    plunge += np.sin(2 * np.pi * (180 + 300 * np.exp(-tt / 0.05)) * tt) * np.exp(-tt / 0.06) * 0.6
    y[n0:] += plunge
    # 气泡：一串上扬的短音
    for _ in range(26):
        start = rng.uniform(0.08, 0.75)
        dur = rng.uniform(0.015, 0.04)
        f = rng.uniform(380, 1300)
        nn = int(dur * SR)
        b = np.arange(nn) / SR
        s = np.sin(2 * np.pi * f * (1 + 2.5 * b / dur) * b) * np.exp(-b / (dur * 0.4))
        i = int(start * SR)
        y[i:i + nn] += s * rng.uniform(0.15, 0.4)
    # 倒水
    p0 = int(1.0 * SR)
    pt = t[: len(t) - p0]
    pour = band(rng.standard_normal(len(pt)), 300, 2800) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 7 * pt + rng.uniform(0, 3))))
    env = np.clip(pt / 0.08, 0, 1) * np.clip((1.1 - pt) / 0.3, 0, 1)
    y[p0:] += pour * env * 0.55
    return fade(y, 0.001, 0.15)


# 喝水 / 小口水声
def sip():
    t = t_axis(0.5)
    y = np.zeros_like(t)
    for _ in range(7):
        start = rng.uniform(0.0, 0.3)
        dur = rng.uniform(0.02, 0.05)
        nn = int(dur * SR)
        b = np.arange(nn) / SR
        f = rng.uniform(300, 700)
        i = int(start * SR)
        y[i:i + nn] += np.sin(2 * np.pi * f * (1 + 1.5 * b / dur) * b) * np.exp(-b / (dur * 0.5))
    return fade(y, 0.001, 0.05)


save("bangzi", bangzi())
save("genggu", genggu())
save("ling", ling())
save("luo", luo())
save("water_draw", water_draw())
save("sip", sip(), 0.6)
save("wind_loop", wind_loop(), 0.7)
