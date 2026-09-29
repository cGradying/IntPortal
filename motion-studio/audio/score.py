"""IntPortal launch score v2: 128 BPM, 61 bars, synthesized from scratch.

Chip-pop: the v1 kick/clap/sub/pad kit plus square/pulse chip voices, a
mid-film "void" (the offline drop: tape stop, near silence, heartbeat) and a
bomb at beat 164.

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


# ---------------------------------------------------------------- chip voices
def pulse(m, dur, duty=0.25, d=None, vib=0.0, bend=0.0):
    """Band-limited-ish pulse wave: NES/Game Boy flavour, low-passed."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = mtof(m) * (1 + vib * np.sin(2 * np.pi * 6 * t) * np.minimum(1, t / 0.15)) * (1 + bend * np.exp(-t / 0.03))
    ph = np.cumsum(f) / SR % 1.0
    y = np.where(ph < duty, 1.0, -1.0)
    y = lp(y, 6500)
    e = np.exp(-t / d) if d else np.minimum(1, (dur - t) / 0.02).clip(0, 1)
    return y * e * np.minimum(1, t / 0.002)


def tri(m, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = mtof(m) * t % 1.0
    y = 4 * np.abs(ph - 0.5) - 1
    y = np.round(y * 8) / 8  # 4-bit stepped like the NES triangle
    return y * np.minimum(1, (dur - t) / 0.01).clip(0, 1)


def heartbeat():
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for off, g in ((0.0, 1.0), (0.17, 0.7)):
        s = int(off * SR)
        tt = t[: n - s]
        f = 42 + 30 * np.exp(-tt / 0.03)
        y[s:] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.12) * g
    return np.tanh(y * 1.5) * 0.8


def sweep_rev(dur):
    """Reverse cymbal-ish swell into the bomb."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = hp(rng.standard_normal(n), 3000) * np.exp(-(dur - t) / (dur * 0.35))
    return x * 0.5


def tape_stop(x, a, b):
    """Replace x[a:b] with a slowing read of the same audio (speed 1 -> 0)."""
    n = b - a
    sp = np.linspace(1, 0, n) ** 1.4
    pos = a + np.cumsum(sp)
    i0 = np.clip(pos.astype(int), 0, len(x) - 2)
    fr = (pos - i0)[:, None]
    y = x[i0] * (1 - fr) + x[i0 + 1] * fr
    fade = np.linspace(1, 0, n) ** 0.5
    x[a:b] = y * fade[:, None]
    x[b:b + int(0.02 * SR)] *= 0


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
chip = np.zeros((N, 2))
pads = np.zeros((N, 2))
fx = np.zeros((N, 2))
duck = np.ones(N)

K = kick()
KB = kick(1.5)
C = clap()


def sidechain(beat, depth=0.75):
    dk = at(beat)
    n = int(0.28 * SR)
    if dk + n < N:
        duck[dk: dk + n] = np.minimum(duck[dk: dk + n], 1 - depth * np.exp(-np.arange(n) / SR / 0.09))


ARP = [0, 2, 1, 3, 2, 0, 3, 1]
HOOK = [3, None, 2, 3, None, 1, 2, None, 0, None, 1, 2, None, 3, 2, None]  # chip lead, 16ths

for bar in range(BARS):
    s = section(bar)
    e = s.get("music", "groove")
    root, notes = chord(bar)
    b0 = bar * 4
    rel = (b0 - s["from"]) // 4  # bar within section

    if e == "hook":
        # cold open: dry 8th glitch stabs + chip blips, stutter on bar 3
        for k in range(8):
            if bar == 3 and k >= 6:
                continue  # hole before the crack
            st = stab([notes[(k * 3) % 4] + 12, notes[(k + 1) % 4]], 1.4)
            st = np.round(st * 24) / 24
            add(synth, st, at(b0 + k * 0.5), 0.8, pan=(-0.6 if k % 2 else 0.6))
            add(chip, pulse(notes[k % 4] + 24, 0.08, 0.125, d=0.04), at(b0 + k * 0.5 + 0.25), 0.22, pan=0.3)
            if k % 2 == 0:
                add(drums, K, at(b0 + k * 0.5), 0.7)
        if bar == 3:  # SESSION EXPIRED x3 stutter on 16ths
            for k in range(6):
                add(synth, np.round(stab([notes[0] + 12], 1.6) * 16) / 16, at(b0 + 1.5 + k * 0.25), 0.7)
        continue

    if e == "form":
        # magnet assembly: pulse kick, 16th chip ticks rising in pitch, pad
        for k in range(4):
            add(drums, K, at(b0 + k), 0.6)
        for k in range(16):
            add(chip, pulse(60 + (rel * 16 + k) % 24, 0.05, 0.5, d=0.02), at(b0 + k * 0.25), 0.14, pan=(-0.5 if k % 2 else 0.5))
        add(pads, pad(notes, BAR, fc=900 + rel * 400), at(b0), 1.2)
        add(bass, sub(root, BAR * 0.98), at(b0), 0.5)
        continue

    if e == "void":
        # the offline drop: almost nothing. Heartbeat on 1 and 3, dark pad.
        for k in (0, 2):
            if b0 + k < 162:
                add(drums, heartbeat(), at(b0 + k), 0.5)
        add(pads, lp(pad(notes, BAR, fc=500), 420), at(b0), 0.9)
        continue

    groove = e in ("groove", "rooms", "drive", "bomb", "anthem")
    big = e in ("bomb", "anthem")

    # kick
    if groove or e in ("intro", "lift", "outro", "build"):
        for k in range(4):
            if e == "build" and rel < 2 and k % 2:
                continue
            g = 1.0 if big else 0.9 if groove else 0.65
            add(drums, KB if (big and k == 0) else K, at(b0 + k), g)
            sidechain(b0 + k, 0.85 if big else 0.75)
    # build: snare roll accelerating into the drop
    if e == "build":
        div = [2, 2, 4, 8][min(rel, 3)]
        for k in range(4 * div):
            if bar == 36 and k >= 4 * div - 2:
                continue
            add(drums, C, at(b0 + k / div), 0.35 + 0.35 * (rel * 4 + k / div) / 16)
    # clap / hats
    if groove:
        for k in (1, 3):
            add(drums, C, at(b0 + k), 0.85 if big else 0.8)
        for k in range(8):
            add(drums, hat(k % 2 == 1), at(b0 + k * 0.5), 0.9 if k % 2 else 0.5, pan=0.25)
        if e in ("drive", "bomb", "anthem"):
            for k in range(16):
                if k % 4 != 0:
                    add(drums, hat(), at(b0 + k * 0.25), 0.35, pan=-0.3)
    if e in ("intro", "lift"):
        for k in range(8):
            add(drums, hat(), at(b0 + k * 0.5), 0.35)

    # bass
    if groove:
        for k in range(8):
            if k % 2 == 0:
                continue
            m = root - 12 if k != 7 else root - 12 + (7 if bar % 2 else 12)
            add(bass, sub(m + 12, BEAT * 0.45), at(b0 + k * 0.5), 1.0)
        if big:
            add(bass, sub(root, BEAT * 0.9), at(b0), 0.7)
    elif e in ("intro", "lift", "build", "outro"):
        add(bass, sub(root, BAR * 0.98), at(b0), 0.7)

    # pads
    fc = {"intro": 1200, "lift": 1800, "groove": 2600, "rooms": 3600, "drive": 4000, "build": 1400 + rel * 900,
          "bomb": 6000, "anthem": 5200, "outro": 2200}.get(e, 2400)
    add(pads, pad(notes, BAR, fc=fc, detune=0.18 if big else 0.12), at(b0), 1.25 if big else 1.0)

    # plucked arp
    if e in ("groove", "drive", "bomb", "anthem", "outro", "lift") or (e == "intro" and rel >= 1):
        for k in range(16):
            m = notes[ARP[k % 8]] + 12
            add(synth, pluck(m, 0.2, 1.3 if big else 1.0), at(b0 + k * 0.25), 0.8 if e != "intro" else 0.5, pan=(0.35 if k % 2 else -0.35))

    # chip arp: 16th pulse, octave-hopping (the pixel signature)
    if e in ("groove", "drive", "bomb", "anthem", "rooms"):
        for k in range(16):
            if e == "groove" and k % 2:
                continue
            m = notes[ARP[(k + 3) % 8]] + 24 + (12 if k % 4 == 3 else 0)
            add(chip, pulse(m, BEAT * 0.22, 0.125 if k % 2 else 0.25, d=0.06), at(b0 + k * 0.25), 0.16, pan=(-0.55 if k % 2 else 0.55))

    # rooms: chord stab + a chip "switch" blip on every beat
    if e == "rooms":
        for k in range(4):
            inv = [n + 12 * ((k + i) % 2) for i, n in enumerate(notes)]
            add(synth, stab(inv, 1.2), at(b0 + k), 1.2, pan=(-0.4 + 0.27 * k))

    # bomb / anthem: chip lead hook + a stepped triangle bass double
    if big:
        for k, idx in enumerate(HOOK):
            if idx is None:
                continue
            m = notes[idx] + (24 if e == "bomb" else 12)
            add(chip, pulse(m, BEAT * 0.4, 0.5 if e == "bomb" else 0.25, d=0.2, vib=0.004), at(b0 + k * 0.25), 0.28)
        add(chip, tri(root + 12, BAR * 0.95), at(b0), 0.18)

    if e == "outro" and bar >= 59:
        pass

# risers + impacts
for r in TL.get("risers", []):
    add(fx, riser((r["to"] - r["from"]) * BEAT), at(r["from"]), r.get("gain", 0.7))
for h in TL.get("impacts", []):
    add(fx, impact(h.get("size", 1.0)), at(h["beat"]), h.get("gain", 0.8))
add(fx, sweep_rev(6 * BEAT), at(158), 0.9)

# ---------------------------------------------------------------- mix
LEVEL = {"hook": 0.8, "form": 0.6, "intro": 0.62, "lift": 0.72, "groove": 0.8, "rooms": 0.88, "drive": 0.86,
         "build": 0.7, "void": 0.14, "bomb": 1.0, "anthem": 0.93, "outro": 0.66}
lvl = np.ones(N)
for bar in range(BARS):
    s_ = section(bar)
    e_ = s_.get("music", "groove")
    g = LEVEL.get(e_, 0.8)
    if e_ == "build":
        g = 0.62 + 0.3 * (bar * 4 - s_["from"]) / 16
    lvl[int(bar * BAR * SR): int((bar + 1) * BAR * SR)] = g
lvl = lp(lvl, 10)
lvl[at(148): at(148) + int(0.05 * SR)] = LEVEL["void"]  # hard cut, not a fade
pads *= duck[:, None]
synth *= (0.55 + 0.45 * duck)[:, None]
chip *= (0.6 + 0.4 * duck)[:, None]
bass *= duck[:, None]
synth = delay(synth, BEAT * 0.75, 0.35, 0.28)
chip = delay(chip, BEAT * 0.5, 0.3, 0.2)
wet_bus = reverb(pads + synth * 0.6 + chip * 0.3, 2.4, 0.3)
music = (drums * 0.9 + bass * 0.95 + wet_bus + synth * 0.4 + chip * 0.55) * lvl[:, None]
ts = TL.get("tapestop")
if ts:
    tape_stop(music, at(ts["from"]), at(ts["to"]))
# the silence just before the bomb: half a beat of nothing
music[at(163.5): at(164)] *= 0.0
mix = music + reverb(fx, 3.0, 0.35, 11)
mix = hp(mix, 25)
fade_from = int(BARS * BAR * SR)
f = np.ones(N)
f[fade_from:] = np.exp(-np.arange(N - fade_from) / SR / 0.8)
mix *= f[:, None]
mix = np.tanh(mix * 0.8) / 0.8
peak = np.abs(mix).max()
mix = mix / peak * 0.89
sf.write(os.path.join(HERE, "music.wav"), mix.astype(np.float32), SR, subtype="FLOAT")
print(f"music.wav {N / SR:.2f}s peak-normalized from {peak:.2f}")
