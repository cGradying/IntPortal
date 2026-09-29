"""IntPortal launch score: 124 BPM, 48 bars, synthesized from scratch.

Writes audio/music.wav (48 kHz stereo float). Deterministic: every noise
source is seeded. Arrangement follows the film's sections (see
../timeline.json); the picture is cut to the grid this file produces, which
beats.py then measures.
"""
import json
import os

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, "..", "timeline.json")))
SR = 48000
BPM = TL["bpm"]
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = TL["bars"]
TAIL = 3.0
N = int((BARS * BAR + TAIL) * SR)
rng = np.random.default_rng(20260929)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def at(beat):
    return int(round(beat * BEAT * SR))


def env_exp(n, decay):
    t = np.arange(n) / SR
    return np.exp(-t / decay)


def lp(x, fc, order=2):
    sos = butter(order, min(fc, SR * 0.45), "low", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def hp(x, fc, order=2):
    sos = butter(order, fc, "high", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], "band", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def saw(freq, n, phase=0.0):
    t = np.arange(n) / SR
    ph = (freq * t + phase) % 1.0
    # polyBLEP-free but band-limited enough after the low-pass
    return 2.0 * ph - 1.0


def add(buf, sig, start, gain=1.0, pan=0.0):
    """Mix mono or stereo `sig` into stereo `buf` at sample `start`."""
    if start >= len(buf):
        return
    if sig.ndim == 1:
        l = np.cos((pan + 1) * np.pi / 4)
        r = np.sin((pan + 1) * np.pi / 4)
        sig = np.stack([sig * l, sig * r], axis=1) * np.sqrt(2)
    end = min(len(buf), start + len(sig))
    if start < 0:
        sig = sig[-start:]
        start = 0
    buf[start:end] += sig[: end - start] * gain


# ---------------------------------------------------------------- instruments
def kick(punch=1.0):
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 46 + 120 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.26)
    click = rng.standard_normal(n) * np.exp(-t / 0.003) * 0.25
    return np.tanh((body + hp(click, 2000)) * 1.6 * punch) * 0.9


def clap():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    e = np.zeros(n)
    for k, d in enumerate([0.0, 0.011, 0.022]):
        s = int(d * SR)
        e[s:] += np.exp(-(t[: n - s]) / (0.008 if k < 2 else 0.12))
    return bp(noise * e, 900, 5200) * 0.55


def hat(open_=False):
    n = int((0.22 if open_ else 0.05) * SR)
    noise = rng.standard_normal(n)
    return hp(noise, 7000, 4) * env_exp(n, 0.07 if open_ else 0.012) * 0.16


def pluck(m, dur=0.22, bright=1.0):
    n = int(dur * SR)
    f = mtof(m)
    x = saw(f, n) + 0.5 * saw(f * 1.004, n, 0.3)
    t = np.arange(n) / SR
    # time-varying low-pass approximated by crossfading two static filters
    hi = lp(x, 5200 * bright)
    lo = lp(x, 700)
    k = np.exp(-t / 0.05)
    y = hi * k + lo * (1 - k)
    return y * np.exp(-t / (dur * 0.45)) * 0.22


def pad(ms, dur, fc=2400, detune=0.12):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for m in ms:
        for v in range(5):
            d = (v - 2) * detune
            f = mtof(m + d / 1.0)
            s = saw(f, n, phase=(v * 0.37 + m * 0.11) % 1)
            pan = (v - 2) / 2.5
            out[:, 0] += s * np.cos((pan + 1) * np.pi / 4)
            out[:, 1] += s * np.sin((pan + 1) * np.pi / 4)
    out = lp(out, fc)
    a = np.minimum(1, t / 0.08) * np.minimum(1, (dur - t) / 0.2).clip(0, 1)
    return out * a[:, None] * 0.045 / max(1, len(ms) ** 0.5)


def sub(m, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    y = np.sin(2 * np.pi * f * t) + 0.35 * lp(saw(f, n), 300)
    a = np.minimum(1, t / 0.01) * np.minimum(1, (dur - t) / 0.03).clip(0, 1)
    return np.tanh(y * 1.3) * a * 0.42


def stab(ms, bright=1.0):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for m in ms:
        for d in (-0.08, 0, 0.08):
            y += saw(mtof(m + d), n, (m * 0.13) % 1)
    y = lp(y, 3800 * bright) * np.exp(-t / 0.16)
    return y * 0.07


def riser(dur, top=9000):
    n = int(dur * SR)
    t = np.arange(n) / SR
    k = t / dur
    noise = rng.standard_normal(n)
    # sweep a band-pass by blocks
    y = np.zeros(n)
    blk = 2048
    for i in range(0, n, blk):
        c = 300 + (top - 300) * (k[i] ** 2.2)
        y[i : i + blk] = bp(noise[i : i + blk + 0], max(80, c * 0.6), min(SR * 0.45, c * 1.4), 1)[: len(y[i : i + blk])]
    f = 180 + 1400 * k**2
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25
    return (y * 0.5 + tone) * (k**1.6) * 0.5


def impact(size=1.0):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    f = 30 + 60 * np.exp(-t / 0.12)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.7)
    noise = lp(rng.standard_normal(n), 3000) * np.exp(-t / 0.25) * 0.35
    return np.tanh((boom + noise) * 1.4) * 0.8 * size


def reverb(x, secs=2.2, mix=0.25, seed=7):
    r = np.random.default_rng(seed)
    n = int(secs * SR)
    t = np.arange(n) / SR
    ir = np.stack([r.standard_normal(n), r.standard_normal(n)], 1) * np.exp(-t / (secs / 5))[:, None]
    ir = lp(ir, 5000)
    ir /= np.sqrt((ir**2).sum(0))
    wet = np.stack([fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], 1)
    return x * (1 - mix) + wet * mix


def delay(x, secs, fb=0.35, mix=0.3):
    d = int(secs * SR)
    y = x.copy()
    for k in range(1, 5):
        g = fb**k
        sh = np.zeros_like(x)
        sh[d * k :] = x[: len(x) - d * k]
        if k % 2:
            sh = sh[:, ::-1]  # ping-pong
        y += sh * g * mix
    return y


# ---------------------------------------------------------------- harmony
# Ab major, vi-IV-I-V: Fm, Db, Ab, Eb (one chord per bar)
CHORDS = [
    (41, [53, 56, 60, 65]),  # Fm
    (37, [49, 53, 56, 61]),  # Db
    (44, [56, 60, 63, 68]),  # Ab
    (39, [51, 55, 58, 63]),  # Eb
]


def chord(bar):
    return CHORDS[bar % 4]


def section(bar):
    for s in TL["sections"]:
        if s["from"] <= bar * 4 < s["to"]:
            return s
    return TL["sections"][-1]


# ---------------------------------------------------------------- arrangement
drums = np.zeros((N, 2))
bass = np.zeros((N, 2))
synth = np.zeros((N, 2))
pads = np.zeros((N, 2))
fx = np.zeros((N, 2))
duck = np.ones(N)

K = kick()
C = clap()

energy = {s["id"]: s.get("energy", 1.0) for s in TL["sections"]}

for bar in range(BARS):
    s = section(bar)
    e = s.get("music", "groove")
    if s["id"] == "sync" and bar * 4 >= s["from"] + 16:
        e = "groove"
    root, notes = chord(bar)
    b0 = bar * 4

    if e == "hook":
        # chaos cuts: 8th-note glitch stabs, dry and bitcrushed
        for k in range(8):
            st = stab([notes[(k * 3) % 4] + 12, notes[(k + 1) % 4]], 1.4)
            st = np.round(st * 24) / 24  # crush
            add(synth, st, at(b0 + k * 0.5), 0.9, pan=(-0.6 if k % 2 else 0.6))
            if k % 2 == 0:
                add(drums, K, at(b0 + k * 0.5), 0.7)
        continue

    if e == "form":
        # portal assembly: pulse + rising blips (block drops are SFX)
        for k in range(4):
            add(drums, K, at(b0 + k), 0.55)
        add(pads, pad(notes, BAR, fc=900), at(b0), 1.2)
        add(fx, riser(BAR, 5000), at(b0), 0.6)
        continue

    groove = e in ("groove", "drop", "rooms", "climax")
    half = e == "half"
    intro = e == "intro"

    # kick
    if groove or intro:
        for k in range(4):
            add(drums, K, at(b0 + k), 0.9 if groove else 0.6)
            dk = at(b0 + k)
            n = int(0.28 * SR)
            if dk + n < N:
                duck[dk : dk + n] = np.minimum(duck[dk : dk + n], 1 - 0.75 * np.exp(-np.arange(n) / SR / 0.09))
    elif half:
        for k in (0, 2.5):
            add(drums, K, at(b0 + k), 0.75)
    # clap / hats
    if groove:
        for k in (1, 3):
            add(drums, C, at(b0 + k), 0.8)
        for k in range(8):
            add(drums, hat(k % 2 == 1), at(b0 + k * 0.5 + 0.0), 0.9 if k % 2 else 0.5, pan=0.25)
        if e in ("drop", "climax"):
            for k in range(16):
                if k % 4 != 0:
                    add(drums, hat(), at(b0 + k * 0.25), 0.35, pan=-0.3)
    if half:
        add(drums, C, at(b0 + 2), 0.8)
        for k in range(4):
            add(drums, hat(True), at(b0 + k + 0.5), 0.45)
    if intro and bar % 2 == 1:
        for k in range(8):
            add(drums, hat(), at(b0 + k * 0.5), 0.35)

    # bass: offbeat pumping 8ths on the root
    if groove or half:
        for k in range(8):
            if groove and k % 2 == 0:
                continue
            m = root - 12 if k != 7 else root - 12 + (7 if bar % 2 else 12)
            add(bass, sub(m + 12, BEAT * 0.45), at(b0 + k * 0.5), 1.0)
        if half:
            add(bass, sub(root, BAR * 0.95), at(b0), 0.8)
    elif intro:
        add(bass, sub(root, BAR * 0.98), at(b0), 0.7)

    # pads
    fc = {"intro": 1100, "half": 1600, "groove": 2600, "drop": 4200, "rooms": 3600, "climax": 5200, "outro": 2000}.get(e, 2400)
    add(pads, pad(notes, BAR, fc=fc), at(b0), 1.0)

    # arps: 16th plucks walking chord tones
    if e in ("groove", "drop", "climax", "half", "outro") or (intro and bar >= 4):
        pat = [0, 2, 1, 3, 2, 0, 3, 1] * 2
        for k in range(16):
            if half and k % 2:
                continue
            m = notes[pat[k]] + 12 + (12 if (k % 8 == 7 and e == "climax") else 0)
            add(synth, pluck(m, 0.2, 1.3 if e == "climax" else 1.0), at(b0 + k * 0.25), 0.9 if not intro else 0.5, pan=(0.35 if k % 2 else -0.35))

    # rooms: a chord stab on every beat (each beat is a new room)
    if e == "rooms":
        for k in range(4):
            inv = [n + 12 * ((k + i) % 2) for i, n in enumerate(notes)]
            add(synth, stab(inv, 1.2), at(b0 + k), 1.3, pan=(-0.4 + 0.27 * k))

    # climax: gold lead, simple motif on top
    if e == "climax":
        motif = [0, None, 2, None, 3, 2, None, 1]
        for k, idx in enumerate(motif):
            if idx is None:
                continue
            add(synth, pluck(notes[idx] + 24, 0.34, 1.6), at(b0 + k * 0.5), 0.8)

    if e == "outro":
        for k in (0, 2):
            add(drums, K, at(b0 + k), 0.55)

# risers + impacts from the timeline
for r in TL.get("risers", []):
    add(fx, riser((r["to"] - r["from"]) * BEAT), at(r["from"]), r.get("gain", 0.7))
for h in TL.get("impacts", []):
    add(fx, impact(h.get("size", 1.0)), at(h["beat"]), h.get("gain", 0.8))

# ---------------------------------------------------------------- mix
LEVEL = {"hook": 0.8, "form": 0.55, "intro": 0.6, "groove": 0.82, "rooms": 0.9, "drop": 0.9,
         "half": 0.58, "climax": 1.0, "outro": 0.62}
lvl = np.ones(N)
for bar in range(BARS):
    s_ = section(bar)
    e_ = s_.get("music", "groove")
    if s_["id"] == "sync" and bar * 4 >= s_["from"] + 16:
        e_ = "build"
    g = LEVEL.get(e_, 0.8)
    if e_ == "build":
        g = 0.62 + 0.3 * (bar * 4 - s_["from"] - 16) / 16
    if e_ == "intro":
        g = 0.55 + 0.25 * (bar * 4 - s_["from"]) / max(1, s_["to"] - s_["from"])
    lvl[int(bar * BAR * SR): int((bar + 1) * BAR * SR)] = g
lvl = lp(lvl, 8)  # smooth the steps a little
pads *= duck[:, None]
synth *= (0.55 + 0.45 * duck)[:, None]
bass *= duck[:, None]
synth = delay(synth, BEAT * 0.75, 0.35, 0.28)
wet_bus = reverb(pads + synth * 0.6, 2.4, 0.3)
mix = (drums * 0.9 + bass * 0.95 + wet_bus + synth * 0.4) * lvl[:, None] + reverb(fx, 3.0, 0.35, 11)
mix = hp(mix, 25)
# final fade after the last bar
fade_from = int(BARS * BAR * SR)
f = np.ones(N)
f[fade_from:] = np.exp(-np.arange(N - fade_from) / SR / 0.8)
mix *= f[:, None]
mix = np.tanh(mix * 0.8) / 0.8
peak = np.abs(mix).max()
mix = mix / peak * 0.89
sf.write(os.path.join(HERE, "music.wav"), mix.astype(np.float32), SR, subtype="FLOAT")
print(f"music.wav {N / SR:.2f}s peak-normalized from {peak:.2f}")
