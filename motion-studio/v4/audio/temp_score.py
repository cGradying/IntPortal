"""Temp score for v4 (stand-in until ElevenLabs Music is reachable).

130 BPM on the film's exact grid (196 beats = 5428 frames), 7 phrases of
7 bars: intro, groove, build, peak, SAX SOLO, full band with sax answers,
outro that resolves into the intro so the file loops. Everything is
synthesized with numpy (seeded): FM Rhodes, sub bass, drums, an arp, and a
formant-filtered saxophone with scoops, vibrato and breath.

    python3 audio/temp_score.py  -> audio/music_temp.wav (48 kHz stereo, loop-wrapped tails)
"""
import os
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, fftconvolve

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 48000
FRAMES, FPS, NB = 5428, 60, 196
DUR = FRAMES / FPS
BEAT = DUR / NB
N = int(round(DUR * SR))
TAIL = int(SR * 3)
rng = np.random.default_rng(130)

L = np.zeros(N + TAIL)
R = np.zeros(N + TAIL)


def at(b):
    return int(round(b * BEAT * SR))


def add(sig, b, gain=1.0, pan=0.0):
    i = at(b)
    j = min(i + len(sig), len(L))
    if j <= i:
        return
    s = sig[: j - i] * gain
    L[i:j] += s * np.sqrt(0.5 * (1 - pan))
    R[i:j] += s * np.sqrt(0.5 * (1 + pan))


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def env(n, a=0.005, d=0.3, s=0.0, r=0.05, hold=None):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4))
    if hold is None:
        e *= np.exp(-t / d) * (1 - s) + s
    else:
        e *= np.where(t < hold, 1.0, np.exp(-(t - hold) / r))
    return e


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


# ---------------------------------------------------------------- instruments
def kick(g=1.0):
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 46 + 90 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7.5) * g + np.exp(-t * 400) * 0.25 * g


def snare(g=1.0):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    nz = bp(rng.standard_normal(n), 1200, 7000) * np.exp(-t * 20)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5
    return (nz * 0.9 + tone) * g


def clap(g=1.0):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    e = sum(np.exp(-np.maximum(t - k * 0.011, 0) * 60) * (t >= k * 0.011) for k in range(3)) + np.exp(-t * 14) * 0.6
    return bp(rng.standard_normal(n), 900, 5000) * e * 0.6 * g


def hat(open_=False, g=1.0):
    n = int((0.32 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7000) * np.exp(-t * (9 if open_ else 70)) * 0.35 * g


def rim(g=1.0):
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 1700 * t) * 0.6 + bp(rng.standard_normal(n), 2000, 6000) * 0.4) * np.exp(-t * 70) * g


def snap(g=1.0):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    return bp(rng.standard_normal(n), 1800, 4500) * np.exp(-t * 55) * 0.8 * g


def rhodes(m, dur_b, g=1.0):
    n = int((dur_b * BEAT + 1.2) * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    idx = 1.6 * np.exp(-t * 3.5) + 0.25
    mod = np.sin(2 * np.pi * f * t) * idx
    car = np.sin(2 * np.pi * f * t + mod) + 0.25 * np.sin(2 * np.pi * 2 * f * t + mod * 0.5) * np.exp(-t * 6)
    e = env(n, 0.003, 1.6, hold=dur_b * BEAT, r=0.35) * np.exp(-t * 0.6)
    trem = 1 + 0.12 * np.sin(2 * np.pi * 4.8 * t)
    return car * e * trem * g


def bass(m, dur_b, g=1.0):
    n = int((dur_b * BEAT + 0.08) * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) + 0.12 * np.sin(6 * np.pi * f * t)
    return lp(s, 900) * env(n, 0.006, 4, hold=dur_b * BEAT - 0.03, r=0.03) * g


def pluck(m, g=1.0):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    saw = 2 * ((f * t) % 1) - 1
    return lp(saw, 2500) * np.exp(-t * 11) * g


def sax(m, dur_b, g=1.0, scoop=True, vib=True):
    """Additive reed tone through vocal-tract-like formants, with a pitch scoop,
    delayed vibrato, breath noise and a soft attack."""
    d = dur_b * BEAT
    n = int((d + 0.12) * SR)
    t = np.arange(n) / SR
    f0 = mtof(m)
    bend = (1 - 0.06 * np.exp(-t * 28)) if scoop else 1.0
    v = 1 + (0.012 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.18) / 0.25, 0, 1) if vib and d > 0.3 else 0)
    f = f0 * bend * v
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = sum((1.0 / k ** 0.9) * np.sin(k * ph) * (1 if k % 2 else 0.75) for k in range(1, 16))
    x = bp(x, 380, 720) * 1.0 + bp(x, 1100, 1900) * 0.7 + bp(x, 2300, 3400) * 0.35 + lp(x, 300) * 0.3
    breath = bp(rng.standard_normal(n), 1500, 5000) * 0.05
    e = np.clip(t / 0.035, 0, 1) * np.where(t < d, 1.0, np.exp(-(t - d) / 0.05))
    growl = 1 + 0.04 * np.sin(2 * np.pi * 31 * t)
    return np.tanh((x + breath) * e * growl * 2.2) * 0.5 * g


# ---------------------------------------------------------------- harmony
CH = {  # Rhodes voicings, bass root
    "Dmaj9": ([62, 66, 69, 73, 76], 38), "Bm9": ([59, 62, 66, 69, 73], 35), "Gmaj9": ([55, 59, 62, 66, 69], 31),
    "A13": ([57, 61, 66, 67, 71], 33), "Em9": ([52, 55, 59, 62, 66], 40), "F#m7": ([54, 57, 61, 64], 42),
}
BARS = ["Dmaj9", "Bm9", "Gmaj9", "A13", "Dmaj9", "Em9", "A13"]  # 7 bars per phrase


def phrase(p):
    b0 = p * 28
    dens = [0.5, 0.85, 0.9, 1.0, 0.6, 0.95, 0.5][p]
    for bar, name in enumerate(BARS):
        bb = b0 + bar * 4
        notes, root = CH[name]
        last = p == 6 and bar == 6
        # Rhodes: intro/outro sustained, groove sections comp on the "and"
        if p in (0, 6, 4):
            for n_ in notes:
                add(rhodes(n_, 3.6, 0.13 if p == 0 else 0.09), bb, pan=(n_ - 64) / 30)
            if p == 4:
                for n_ in notes[1:4]:
                    add(rhodes(n_ + 12, 0.4, 0.035), bb + 2.5, pan=0.3)
        else:
            for k, off in enumerate([0, 1.5, 2.5, 3.5] if p != 3 else [0, 1, 2, 3]):
                for n_ in notes:
                    add(rhodes(n_, 0.45 if off else 1.3, 0.07 * (1.15 if off == 0 else 0.85)), bb + off, pan=(n_ - 64) / 30)
        # bass
        if p in (1, 2, 3, 4, 5):
            pat = [(0, 1.5, 0), (1.5, 0.5, 0), (2, 0.75, 7), (2.75, 0.25, 5), (3, 1, 0)]
            if p == 2 and bar % 2 == 1:
                pat = [(0, 1, 0), (1, 1, 2), (2, 1, 4), (3, 1, 5)]
            for off, d_, iv in pat:
                add(bass(root + iv, d_, 0.42), bb + off)
        elif p == 6 and bar < 5:
            add(bass(root, 3.8, 0.3), bb)
        # drums: something on every beat
        for beat in range(4):
            b = bb + beat
            if p in (0, 6):
                add(kick(0.75 if p == 0 else 0.6), b)
                add(hat(False, 0.3), b + 0.5, pan=0.3)
                if beat % 2 == 1:
                    add(snap(0.5), b)
            elif p == 4:
                add(kick(0.7), b) if beat in (0, 2) else add(rim(0.35), b, pan=0.25)
                add(rim(0.18), b + 0.75, pan=-0.3)
                add(hat(False, 0.5), b + 0.5, pan=0.35)
            else:
                if beat in (0, 2) or (p == 3):
                    add(kick(0.85), b)
                if beat in (1, 3):
                    add(snare(0.55), b)
                    if p >= 2:
                        add(clap(0.6), b)
                for s16 in range(4 if p != 1 else 2):
                    add(hat(p == 3 and s16 == 2, 0.6 if s16 % 2 == 0 else 0.35), b + s16 * (1 if p == 1 else 0.25) * (0.5 if p == 1 else 1), pan=0.3)
        # arp in build / peak
        if p in (2, 3):
            for s in range(8):
                add(pluck(notes[s % len(notes)] + 12 + (12 if s >= 4 and p == 3 else 0), 0.09 * dens * (1 + bar / 10)), bb + s * 0.5, pan=-0.35 + 0.1 * (s % 3))
        if last:
            pass


for p in range(7):
    phrase(p)

# ---------------------------------------------------------------- saxophone
SOLO = [  # (beat in phrase 5, length in beats, midi)
    (0, .5, 69), (.5, .5, 71), (1, 1, 74), (2, .75, 78), (2.75, .25, 76), (3, 1, 74),
    (4, .5, 71), (4.5, .5, 69), (5, .5, 66), (5.5, .5, 69), (6, 1.5, 71), (7.5, .5, 74),
    (8, .5, 76), (8.5, .5, 78), (9, 1, 81), (10, .5, 78), (10.5, .25, 76), (10.75, .25, 74), (11, 1, 76),
    (12.5, .25, 74), (12.75, .25, 76), (13, .5, 78), (13.5, .5, 76), (14, .5, 74), (14.5, .5, 71), (15, 1, 69),
    (16, .75, 81), (16.75, .25, 79), (17, .5, 78), (17.5, .5, 76), (18, .5, 77), (18.5, .5, 76), (19, 1, 74),
    (20, .25, 71), (20.25, .25, 74), (20.5, .25, 76), (20.75, .25, 78), (21, .5, 81), (21.5, 1, 83), (22.5, .5, 81), (23, 1, 78),
    (24, .5, 76), (24.5, .5, 74), (25, .5, 71), (25.5, .5, 69), (26, 2, 74),
]
for off, d, m in SOLO:
    add(sax(m - 12, d * 0.96, 0.55, scoop=d >= 0.5), 112 + off, pan=0.08)
ANSWERS = [(6, .5, 78), (6.5, .5, 76), (7, 1, 74), (14, .5, 69), (14.5, .5, 71), (15, 1, 74),
           (22, .5, 81), (22.5, .5, 78), (23, .5, 76), (23.5, .5, 74), (26, 1.5, 74)]
for off, d, m in ANSWERS:
    add(sax(m - 12, d * 0.96, 0.42), 140 + off, pan=-0.1)

# ---------------------------------------------------------------- space + loop wrap
ir_n = int(1.4 * SR)
tt = np.arange(ir_n) / SR
irL = rng.standard_normal(ir_n) * np.exp(-tt * 4.2)
irR = rng.standard_normal(ir_n) * np.exp(-tt * 4.2)
irL[: int(0.012 * SR)] = 0
irR[: int(0.017 * SR)] = 0
wet = 0.07
L2 = L + fftconvolve(lp(L, 6000), irL)[: len(L)] * wet
R2 = R + fftconvolve(lp(R, 6000), irR)[: len(R)] * wet
# tails past the loop point wrap onto the head, so the file loops seamlessly
L2[:TAIL] += L2[N:]
R2[:TAIL] += R2[N:]
out = np.stack([L2[:N], R2[:N]], axis=1)
out /= np.max(np.abs(out)) / 0.7
sf.write(os.path.join(HERE, "music_temp.wav"), out.astype(np.float32), SR)
print("music_temp.wav", f"{N / SR:.3f}s")
