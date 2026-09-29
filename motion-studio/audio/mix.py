"""SFX + VO + music → audio/mix.wav at -14 LUFS / -1 dBTP.

Every SFX is synthesized here and placed on the measured beat grid
(beats.json) at the cue beats the film uses. VO takes are placed at their
script beats; the music ducks under speech. Loudness: ffmpeg loudnorm, 2-pass.
"""
import json
import os
import subprocess

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SR = 48000
BEATS = json.load(open(os.path.join(ROOT, "beats.json")))["beats"]
BEAT = 60 / 128
rng = np.random.default_rng(7)


def tb(n):
    i = int(np.floor(n))
    if i >= len(BEATS) - 1:
        return BEATS[-1] + (n - len(BEATS) + 1) * BEAT
    return BEATS[i] + (BEATS[i + 1] - BEATS[i]) * (n - i)


def filt(x, kind, f, order=2):
    return sosfilt(butter(order, f, kind, fs=SR, output="sos"), x)


def env(n, a=0.002, d=0.1):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)


def tone(f, dur, d=0.1, a=0.002, wave="sine"):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.broadcast_to(f, (n,)) if np.ndim(f) else np.full(n, f)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) if wave == "sine" else (2 * ((np.cumsum(f) / SR) % 1) - 1)
    return y * env(n, a, d)


def noise(dur):
    return rng.standard_normal(int(dur * SR))


# ----------------------------------------------------------------- SFX set
def thunk(size=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(90 + 140 * np.exp(-t / 0.02)) / SR) * np.exp(-t / 0.09)
    slap = filt(noise(0.45), "bandpass", [600, 3500]) * np.exp(-t / 0.018) * 0.7
    return np.tanh((body + slap) * 1.8) * 0.7 * size


def click(p=1.0):
    n = int(0.05 * SR)
    return filt(noise(0.05), "highpass", 2500) * env(n, 0.0005, 0.006) * 0.5 * p + tone(1800 * p, 0.05, 0.01) * 0.25


def blip(f=1400, dur=0.09):
    t = np.arange(int(dur * SR)) / SR
    return tone(f * (1 + 0.5 * np.exp(-t / 0.02)), dur, 0.03) * 0.35


def pop(f=700):
    t = np.arange(int(0.12 * SR)) / SR
    return tone(f * (1.8 - 0.8 * np.exp(-t / 0.01)), 0.12, 0.035) * 0.45


def whoosh(dur=0.5, up=True, bright=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    k = t / dur
    x = noise(dur)
    lo = filt(x, "bandpass", [300, 1400])
    hi = filt(x, "bandpass", [1800, 7000 * bright])
    mixk = k if up else 1 - k
    shape = np.sin(np.pi * np.clip(k, 0, 1)) ** (1.4 if up else 0.8)
    return (lo * (1 - mixk) + hi * mixk) * shape * 0.35


def thud(size=1.0):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * np.cumsum(55 + 70 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.12) * 0.8 * size


def flip():
    return filt(noise(0.16), "bandpass", [1500, 6000]) * env(int(0.16 * SR), 0.03, 0.05) * 0.35


def riffle(count=7, gap=0.035):
    out = np.zeros(int((count * gap + 0.2) * SR))
    for i in range(count):
        s = flip() * (0.6 + 0.05 * i)
        st = int(i * gap * SR)
        out[st : st + len(s)] += s
    return out


def ignite(f=220, dur=0.9):
    t = np.arange(int(dur * SR)) / SR
    sweep = f * (1 + 1.2 * (1 - np.exp(-t / 0.08)))
    body = tone(sweep, dur, 0.35, 0.005, "saw")
    body = filt(body, "lowpass", 3200)
    air = filt(noise(dur), "bandpass", [2000, 9000]) * np.exp(-t / 0.25) * 0.3
    return (body * 0.35 + air) * 0.7


def chime(notes=(76, 83, 88), gap=0.07):
    out = np.zeros(int((len(notes) * gap + 0.9) * SR))
    for i, m in enumerate(notes):
        f = 440 * 2 ** ((m - 69) / 12)
        s = tone(f, 0.9, 0.3) * 0.25 + tone(f * 2, 0.9, 0.15) * 0.08
        st = int(i * gap * SR)
        out[st : st + len(s)] += s
    return out


def ticker(dur, rate=24):
    out = np.zeros(int(dur * SR) + SR // 10)
    for i in range(int(dur * rate)):
        s = click(0.7 + 0.3 * (i / max(1, dur * rate)))
        st = int(i / rate * SR)
        out[st : st + len(s)] += s * 0.5
    return out


def glitch(dur=0.5):
    x = np.zeros(int(dur * SR))
    for i in range(0, len(x), 1200):
        if rng.random() > 0.4:
            f = rng.choice([300, 600, 1200, 2400])
            s = tone(f, 1200 / SR, 0.02, wave="saw") * 0.3
            x[i : i + len(s)] += s[: len(x[i : i + len(s)])]
    return x


def zip_(dur=0.3):
    t = np.arange(int(dur * SR)) / SR
    return tone(600 + 3000 * (t / dur) ** 2, dur, dur, 0.005) * np.sin(np.pi * t / dur) * 0.2


def boing(up=True):
    t = np.arange(int(0.28 * SR)) / SR
    f = 260 * (1 + (1.2 if up else -0.5) * (t / 0.28)) * (1 + 0.05 * np.sin(2 * np.pi * 18 * t))
    return tone(f, 0.28, 0.12) * 0.35


def sparkle(dur=0.8):
    out = np.zeros(int(dur * SR) + SR // 5)
    for i in range(14):
        m = 84 + int(rng.integers(0, 12))
        s = tone(440 * 2 ** ((m - 69) / 12), 0.15, 0.05) * 0.12
        st = int(rng.random() * dur * SR)
        out[st : st + len(s)] += s
    return out


def ripple():
    a, w = chime((72, 79, 84, 91), 0.05) * 0.9, whoosh(0.9, False, 0.8) * 0.6
    a[: len(w)] += w
    return a


def step():
    return filt(noise(0.06), "lowpass", 1200) * env(int(0.06 * SR), 0.001, 0.015) * 0.35


# v2 additions
def snap(p=1.0):
    """Magnet weld: short FM tick + metallic ping."""
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    tick = np.sin(2 * np.pi * 2400 * p * t + 3 * np.sin(2 * np.pi * 380 * t)) * np.exp(-t / 0.006)
    ping = (np.sin(2 * np.pi * 1850 * p * t) + 0.5 * np.sin(2 * np.pi * 2710 * p * t)) * np.exp(-t / 0.07) * 0.35
    return (tick * 0.5 + ping) * 0.45


def switch_(g=1.0):
    """8-bit latch: two square blips, low then high."""
    out = np.zeros(int(0.12 * SR))
    for off, f in ((0.0, 520), (0.035, 1040)):
        n = int(0.03 * SR)
        t = np.arange(n) / SR
        sq = np.sign(np.sin(2 * np.pi * f * t)) * np.exp(-t / 0.02)
        st = int(off * SR)
        out[st:st + n] += sq * 0.25
    out = filt(out, "lowpass", 7000) * g
    c = click(1.1) * 0.5 * g
    out[: len(c)] += c
    return out


def slice_():
    t = np.arange(int(0.25 * SR)) / SR
    return filt(noise(0.25), "bandpass", [3000, 9000]) * np.exp(-t / 0.04) * 0.5 + tone(3200 * np.exp(-t / 0.05) + 400, 0.25, 0.05) * 0.15


def err():
    return filt(tone(180, 0.28, 0.2, wave="saw"), "lowpass", 1400) * 0.45


def wifi_drop(i=0):
    out = np.zeros(int(0.5 * SR))
    for k in range(4):
        f = 1400 * 2 ** (-(k + i) / 5)
        s = np.sign(np.sin(2 * np.pi * f * np.arange(int(0.06 * SR)) / SR)) * np.exp(-np.arange(int(0.06 * SR)) / SR / 0.04) * 0.18
        st = int(k * 0.08 * SR)
        out[st:st + len(s)] += s
    return filt(out, "lowpass", 5000)


def hum(dur):
    t = np.arange(int(dur * SR)) / SR
    f = 70 + 90 * (t / dur) ** 1.5
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR)
    return y * (t / dur) ** 1.2 * np.minimum(1, (dur - t) / 0.05) * 0.25


def crack():
    t = np.arange(int(0.6 * SR)) / SR
    body = thud(1.1)
    return filt(noise(0.6), "highpass", 1500) * np.exp(-t / 0.08) * 0.6 + np.pad(body, (0, len(t) - len(body)))


# ----------------------------------------------------------------- cues
C = []  # (beat, signal, gain, pan)


def cue(b, s, g=1.0, pan=0.0):
    C.append((b, s, g, pan))


# ---- cold open
for b in (0.0, 0.5, 1.0, 1.5):
    cue(b, thud(0.8), 0.7)
    cue(b, glitch(0.12), 0.5, 0.2)
cue(1.25, click(1.2), 0.7, 0.6)
for i, b in enumerate(np.arange(2.75, 4.9, 0.125)):
    cue(b, step(), 0.7, 0.3 + 0.1 * (i % 3))
cue(5.0, click(), 1.0, 0.3)
cue(6.5, thunk(1.3), 1.0)
cue(8.5, click(), 1.0, 0.3)
for i, b in enumerate(np.arange(9.0, 10.5, 0.0625)):
    cue(b, step(), 0.6, 0.3 + 0.1 * (i % 3))
cue(10.75, err(), 0.8, 0.3)
cue(11.5, click(), 1.0, 0.3)
for b in (9, 12):
    cue(b, click(1.2), 0.6, 0.6)
for b in (13.5, 13.75, 14.0, 14.25, 14.5):
    cue(b, thunk(0.8), 0.7)
    cue(b, glitch(0.2), 0.6)
cue(15, crack(), 1.0)
cue(15, whoosh(0.6, False, 1.2), 0.7)
# ---- magnet portal
cue(16, whoosh(0.5, False, 0.8), 0.5)
cue(16.5, hum(tb(23) - tb(16.5)), 0.8)
for n in range(24):
    cue(17 + n * 0.25, snap(1 + 0.02 * n), 0.75, 0.5 * np.sin(n))
cue(23, whoosh(tb(24) - tb(23), True, 1.2), 0.7)
cue(24, ignite(110, 1.6), 0.9)
cue(25, sparkle(0.4), 0.6)
cue(25.75, pop(620), 0.8)
cue(25.8, boing(True), 0.6)
cue(26.5, chime((76, 83, 88)), 0.6)
cue(27, whoosh(0.3, True), 0.4, -0.4)
cue(29, zip_(0.35), 0.5, -0.4)
cue(30, switch_(1.2), 1.0, -0.4)
cue(31, zip_(tb(31.75) - tb(31)), 0.7)
cue(31.75, pop(900), 0.5)
cue(32, whoosh(tb(35.4) - tb(32), True, 1.3), 1.0)
# ---- iOS
cue(35.9, whoosh(0.5, False), 0.8)
cue(36, thud(1.0), 0.8)
cue(38.5, zip_(0.3), 0.4, 0.4)
cue(41.5, boing(False), 0.5, 0.4)
for b in (40, 55, 77, 85):
    cue(b, zip_(0.3), 0.5, -0.2)
    cue(b + 0.6, blip(1500, 0.08), 0.5, 0.2)
for b in (44, 52, 68, 84, 90.5):
    cue(b, blip(1600, 0.08), 0.55, 0.3)
for b in (52, 68, 84):
    cue(b - 0.15, whoosh(0.35, True, 0.9), 0.5)
    cue(b + 0.5, glitch(0.15), 0.4, -0.4)
for i in range(10):
    cue(52.5 + i * 0.25, pop(700 + 60 * i), 0.4, (i % 2) * 0.4 - 0.2)
cue(60, whoosh(0.6, True), 0.6)
cue(68.3, ticker(tb(70.4) - tb(68.3), 22), 0.6)
for i, b in enumerate((72, 73, 74, 75)):
    cue(b, thunk(0.9 + 0.05 * i), 0.9, -0.2 + 0.1 * i)
cue(77, ticker(tb(79.4) - tb(77), 16), 0.35)
cue(88, slice_(), 0.9)
for i in range(10):
    cue(88.9 + i * 0.15, snap(1.2 + 0.03 * i), 0.4, (i % 3 - 1) * 0.3)
cue(90.5, whoosh(0.3, True), 0.5)
cue(91, riffle(7), 0.8)
cue(93, flip(), 0.9)
cue(96.4, flip(), 0.9)
cue(94.9, click(), 0.8)
cue(97.3, click(), 0.8)
cue(95, whoosh(0.3, False), 0.5, 0.5)
cue(97.4, whoosh(0.3, False), 0.5, 0.5)
cue(99.2, whoosh(tb(100) - tb(99.2), True, 1.0), 0.6)
# ---- edit mid-anim / rooms
cue(100, whoosh(0.6, False, 0.8), 0.6)
for b in (102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 114):
    cue(b, switch_(), 0.9, 0.6)
cue(111.2, boing(True), 0.6, 0.5)
cue(112, switch_(1.3), 1.0, 0.6)
cue(112, pop(980), 0.5, 0.6)
cue(114.8, whoosh(tb(116) - tb(114.8), True, 1.1), 0.7)
# ---- iOS · Mac · PC
cue(116, thud(1.0), 0.8)
for b in (117.5, 120.5):
    cue(b - 0.2, whoosh(0.3, False), 0.5)
    cue(b, thud(0.9), 0.8)
for i in range(4):
    for a0 in (117, 120):
        cue(a0 + i * 0.25, zip_(0.25), 0.35, 0.3 * (i - 1.5))
        cue(a0 + i * 0.25 + 0.9, snap(1.1), 0.6, 0.3 * (i - 1.5))
cue(123.4, whoosh(0.8, False, 0.7), 0.5)
for i in range(3):
    cue(124 + i * 0.25, thunk(0.9), 0.8, (i - 1) * 0.5)
cue(124.8, glitch(0.2), 0.4)
# ---- PUP SIS
cue(132, whoosh(0.6, False), 0.6, -0.5)
cue(134.5, chime((79, 84)), 0.7, -0.4)
cue(135, pop(640), 0.5, -0.5)
cue(136, zip_(0.4), 0.6)
for i in range(6):
    cue(137 + i * 0.5, blip(1200 + 80 * i, 0.07), 0.5, -0.4)
    cue(138.4 + i * 0.5, pop(760 + 40 * i), 0.45, 0.5)
cue(142, ripple(), 0.9)
cue(143.9, glitch(0.3), 0.6, -0.5)
cue(144, ignite(196, 0.6), 0.4, -0.5)
# ---- the drop
for i, b in enumerate((152, 153, 154, 155)):
    cue(b, wifi_drop(i), 0.9)
cue(155.4, err(), 0.35)
cue(156, switch_(1.8), 1.3, 0.3)
cue(157.4, step(), 0.4)
cue(160, blip(1800, 0.08), 0.4)
# ---- bomb → AI
cue(164, thunk(1.4), 1.0)
cue(164, glitch(0.4), 0.7)
cue(164.3, pop(700), 0.6, 0.6)
cue(166, glitch(0.2), 0.4)
cue(168, riffle(9, 0.03), 0.8, 0.3)
for i in range(3):
    cue(169.5 + i * 0.15, slice_(), 0.7, 0.3 * (i - 1))
for i in range(12):
    cue(171 + i * 0.08, blip(900 + 90 * i, 0.06), 0.35, 0.3)
cue(175, whoosh(0.4, True), 0.5, -0.4)
cue(175.8, zip_(tb(176.8) - tb(175.8)), 0.7)
cue(177, chime((84, 88, 91)), 0.7, 0.4)
for i in range(3):
    cue(180.3 + i * 0.5, snap(1.3), 0.6, -0.4)
cue(180.2, ticker(tb(182.6) - tb(180.2), 18), 0.35, -0.4)
cue(183.5, whoosh(0.6, False), 0.5)
for b in (186, 187.5, 189, 190.5, 192):
    for k in range(4):
        cue(b + k * 0.1, snap(1 + 0.1 * k), 0.4, (k - 1.5) * 0.3)
    cue(b + 0.55, thunk(0.7), 0.6)
cue(193.2, whoosh(0.5, True, 0.8), 0.5)
cue(194, pop(900), 0.6, 0.6)
cue(199.3, whoosh(tb(200) - tb(199.3), True, 1.2), 0.7)
# ---- the network
cue(201, glitch(0.5), 0.6)
cue(201, ignite(196, 0.8), 0.5)
scale = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31, 33, 36]
for i in range(16):
    cue(202.15 + i * 0.5, ignite(110 * 2 ** (scale[i] / 12), 0.6), 0.45, 0.4 * np.sin(i))
cue(209.2, whoosh(tb(213.5) - tb(209.2), True, 0.8), 0.7)
for i in range(16):
    cue(212 + i * 0.12, zip_(0.25), 0.3, 0.4 * np.cos(i))
cue(214, ticker(tb(220.5) - tb(214), 22), 0.4)
cue(218, pop(1100), 0.6)
cue(216, sparkle(1.2), 0.5)
# ---- Beta Pass IDs
cue(224, whoosh(0.5, True), 0.6)
for i in range(1, 10):
    cue(225 + (i - 1) * 0.8, glitch(0.12), 0.5, 0.2)
    cue(225 + (i - 1) * 0.8, blip(1300 + 60 * i, 0.06), 0.5, 0.2)
cue(225.5, thunk(1.2), 0.9)
cue(233.2, riffle(10, 0.03), 0.9)
cue(234.6, whoosh(0.5, True), 0.6)
cue(235, pop(620), 0.6)
for i in range(4):
    cue(235.8 + i * 0.25, ticker(0.18, 30), 0.5, 0.3)
    cue(236.25 + i * 0.25, click(1.2), 0.8, 0.3)
cue(237.6, whoosh(0.6, False, 1.0), 0.6)
cue(237.9, ignite(110, 1.2), 0.7)
cue(240, chime((76, 83, 88, 95)), 0.7)
cue(242.8, zip_(tb(243.5) - tb(242.8)), 0.6)
cue(243.5, pop(1000), 0.6)

# ----------------------------------------------------------------- build
music, sr = sf.read(os.path.join(HERE, "music.wav"), always_2d=True)
assert sr == SR
N = len(music)
sfx = np.zeros((N, 2))
for b, s, g, pan in C:
    st = int(tb(b) * SR)
    if st >= N:
        continue
    s = s[: N - st]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    sfx[st : st + len(s), 0] += s * g * l * 1.2
    sfx[st : st + len(s), 1] += s * g * r * 1.2

# VO
S = json.load(open(os.path.join(HERE, "vo", "script.json")))
vo = np.zeros(N)
for line in S["lines"]:
    parts = []
    for who in line["who"]:
        a, r = sf.read(os.path.join(HERE, "vo", "takes", f"{line['id']}_{who}.wav"))
        parts.append(a)
    L = max(len(p) for p in parts)
    take = sum(np.pad(p, (0, L - len(p))) for p in parts) / (1 if len(parts) == 1 else 1.3)
    take = filt(take, "highpass", 90)
    take = take / (np.abs(take).max() + 1e-9) * 0.9 * 10 ** (line.get("gain_db", 0) / 20)
    if line.get("close"):
        take = filt(take, "lowpass", 6500)
    st = int(tb(line["beat"]) * SR)
    vo[st : st + L] += take[: N - st]
# gentle room on the VO
ir = rng.standard_normal(int(0.35 * SR)) * np.exp(-np.arange(int(0.35 * SR)) / SR / 0.06)
ir /= np.sqrt((ir**2).sum())
vo = vo * 0.92 + fftconvolve(vo, ir)[:N] * 0.12
# duck music under VO (smooth envelope follower)
lvl = np.abs(vo)
win = int(0.02 * SR)
lvl = np.convolve(lvl, np.ones(win) / win, mode="same")
gate = (lvl > 0.02).astype(float)
k = int(0.15 * SR)
gate = np.convolve(gate, np.ones(k) / k, mode="same")
duck = 1 - 0.5 * np.clip(gate * 1.5, 0, 1)
mix = music * duck[:, None] * 0.8 + sfx * 0.55 + vo[:, None] * 0.95
raw = os.path.join(HERE, "mix_raw.wav")
sf.write(raw, mix.astype(np.float32), SR, subtype="FLOAT")

# loudness: static gain to -14 LUFS, then an oversampled limiter for true peak.
# (loudnorm would fall back to dynamic mode here and flatten the drop.)
out = os.path.join(HERE, "mix.wav")


def measure(path):
    e = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "loudnorm=I=-14:TP=-1.0:LRA=20:print_format=json", "-f", "null", "-"], capture_output=True, text=True).stderr
    return json.loads(e[e.rindex("{") : e.rindex("}") + 1])


gain = -14 - float(measure(raw)["input_i"])
for _ in range(3):
    af = f"volume={gain:.2f}dB,aresample=192000,alimiter=limit=0.84:level=false:attack=1:release=60,aresample=48000"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", af, "-ar", "48000", "-c:a", "pcm_s24le", out], check=True)
    m = measure(out)
    err_ = -14 - float(m["input_i"])
    print(f"gain {gain:.2f} dB → {m['input_i']} LUFS, {m['input_tp']} dBTP")
    if abs(err_) < 0.2:
        break
    gain += err_
print(f"{len(C)} SFX cues, {len(S['lines'])} VO lines → mix.wav")
