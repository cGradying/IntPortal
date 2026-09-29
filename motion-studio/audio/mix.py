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
BEAT = 60 / 124
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


# ----------------------------------------------------------------- cues
C = []  # (beat, signal, gain, pan)


def cue(b, s, g=1.0, pan=0.0):
    C.append((b, s, g, pan))


# hook
cue(0, thunk(0.8), 0.6)
for b in (0.0, 0.5, 1.0, 1.5):
    cue(b, thud(0.8), 0.7)
    cue(b, whoosh(0.18, False, 1.2), 0.6)
for b in (3.0, 3.5, 4.0, 4.5, 5.0):
    cue(b, click(), 0.9, 0.3)
cue(6.5, thunk(1.2), 1.0)
cue(6.95, whoosh(0.7, False, 0.9), 0.8)
for i in range(12):
    cue(6.9 + i / 12, thud(0.35 + 0.02 * i), 0.5, (i % 3 - 1) * 0.3)
cue(8, ignite(110, 1.6), 0.9)
for i in range(4):
    cue(7.9 + i * 0.27, step(), 0.8, -0.4)
cue(9, thud(0.5), 0.5)
cue(11.6, whoosh(0.4, True), 0.4, 0.4)
cue(12, pop(620), 0.6, 0.4)
cue(14, click(1.2), 1.0, 0.4)
cue(14, pop(900), 0.5, 0.4)
cue(15, boing(True), 0.8)
cue(16, whoosh(tb(19.4) - tb(16), True, 1.3), 1.0)
# ios
cue(19.8, whoosh(0.5, False), 0.8)
cue(20, thud(1.0), 0.8)
for b in (24, 26, 36, 48, 60):
    cue(b, blip(1600, 0.08), 0.6, -0.2)
cue(25, whoosh(0.3, True, 0.7), 0.4)
for b in (28, 36, 48, 60):
    cue(b - 0.15, whoosh(0.35, True, 0.9), 0.5)
for i in range(10):
    cue(28.4 + i * 0.25, pop(700 + 60 * i), 0.4, (i % 2) * 0.4 - 0.2)
cue(32, whoosh(0.6, True), 0.6)
cue(36.2, ticker(tb(38.4) - tb(36.2), 22), 0.6)
for i, b in enumerate((40, 41, 42, 43)):
    cue(b, thunk(0.9 + 0.05 * i), 0.9, -0.2 + 0.1 * i)
cue(44, ticker(tb(46.2) - tb(44), 16), 0.35)
cue(50, riffle(7), 0.8)
cue(52, flip(), 0.8)
cue(54, flip(), 0.9)
cue(57.4, flip(), 0.9)
cue(55.9, click(), 0.8)
cue(58.5, click(), 0.8)
cue(56, whoosh(0.3, False), 0.5, 0.5)
cue(58.6, whoosh(0.3, False), 0.5, 0.5)
cue(60, boing(True), 0.7)
cue(60.8, pop(820), 0.6)
cue(67.1, whoosh(tb(68.2) - tb(67.1), True, 1.2), 0.8)
# rooms
for i in range(16):
    cue(68 + i, click(1.0 + 0.04 * i), 0.55, 0.3 * ((i % 2) * 2 - 1))
cue(70, pop(980), 0.35)
# platforms
for b in (84, 86, 90, 94, 98):
    cue(b - 0.2, whoosh(0.3, False), 0.5)
    cue(b + 0.05, thud(0.9), 0.8)
for b in (88.5, 93.5, 97.5, 100.5):
    cue(b, whoosh(0.9, True, 0.8), 0.5)
cue(103.6, click(1.1), 0.9)
cue(104, thunk(1.0), 0.9)
for i in range(1, 5):
    cue(104 + i * 0.12, thunk(0.5), 0.5, (i - 2.5) * 0.3)
# sync
cue(107.6, whoosh(0.6, False), 0.6, -0.5)
cue(111.5, chime((79, 84)), 0.7, -0.4)
for i in range(3):
    cue(112 + i * 0.5, pop(640 + i * 90), 0.5, -0.5)
for i in range(6):
    cue(113 + i * 0.75, blip(1200 + 80 * i, 0.07), 0.5, -0.4)
    cue(113 + i * 0.75, zip_(tb(114.1) - tb(113)), 0.6, 0.2)
cue(120, ripple(), 0.9)
cue(124.3, whoosh(0.4, True), 0.5)
cue(125.2, pop(760), 0.6)
cue(126.2, sparkle(tb(128.6) - tb(126.2)), 0.8)
cue(129, pop(980), 0.5)
for i in range(8):
    cue(132 + i, thud(0.6 + 0.05 * i), 0.55)
    cue(132 + i, whoosh(0.2, False, 1.3), 0.4)
# hub
cue(142.3, glitch(0.5), 0.6)
cue(142.3, ignite(196, 0.8), 0.5)
scale = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26]
for i in range(12):
    cue(144 + i, ignite(110 * 2 ** (scale[i] / 12), 0.8), 0.55, 0.4 * np.sin(i))
cue(156.5, whoosh(tb(162) - tb(156.5), True, 0.8), 0.7)
cue(158, sparkle(1.4), 0.6)
for i in range(12):
    cue(161.5 + i * 0.5, zip_(0.35), 0.5, 0.4 * np.cos(i))
for b in (164, 165.5, 167):
    cue(b, pop(700), 0.6, -0.4)
# outro
cue(173.3, whoosh(0.5, True), 0.6, 0.3)
cue(176, thunk(1.3), 1.0)
for i in range(22):
    cue(176.5 + i * 0.125, click(1.3), 0.35, 0.2)
cue(179, pop(620), 0.7)
for i in range(5):
    cue(180.5 + i * 0.3, step(), 0.7, 0.5)
cue(182, pop(900), 0.4, -0.2)
cue(186, whoosh(tb(187.8) - tb(186), True, 1.1), 0.8)

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
    take = take / (np.abs(take).max() + 1e-9) * 0.9
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

# loudnorm 2-pass → -14 LUFS, -1 dBTP
out = os.path.join(HERE, "mix.wav")
p1 = subprocess.run(["ffmpeg", "-hide_banner", "-i", raw, "-af", "loudnorm=I=-14:TP=-1.0:LRA=11:print_format=json", "-f", "null", "-"], capture_output=True, text=True).stderr
m = json.loads(p1[p1.rindex("{") : p1.rindex("}") + 1])
af = (f"loudnorm=I=-14:TP=-1.0:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
      f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true,aresample=192000,alimiter=limit=0.84:level=false:attack=1:release=40,aresample=48000")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", af, "-ar", "48000", "-c:a", "pcm_s24le", out], check=True)
print(f"{len(C)} SFX cues, {len(S['lines'])} VO lines → mix.wav")
