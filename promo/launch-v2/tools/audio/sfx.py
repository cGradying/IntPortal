"""Synthesised sound effects, triggered from the cue sheet so picture and sound share one clock."""
import numpy as np
from dsp import *  # noqa
from music import _hit, _fm_bell, midi


def _stereo(x, p=0.0):
    return pan(x, p) if x.ndim == 1 else x


def hit(size=1.0, seed=11):
    return _hit(dur=1.6, size=size, seed=seed)


def clack(pitch=1.0, seed=0):
    n = int(0.09 * SR)
    tt = t_axis(n)
    nz = filt(noise(n, seed), "bp", 1400 * pitch, 1.2) * np.exp(-tt / 0.012)
    tone = np.sin(2 * np.pi * 240 * pitch * tt) * np.exp(-tt / 0.025)
    return (nz * 0.8 + tone * 0.6) * 0.55


def word(pitch=1.0):
    n = int(0.22 * SR)
    tt = t_axis(n)
    thud = np.sin(2 * np.pi * np.cumsum(110 * pitch * (1 + 1.2 * np.exp(-tt / 0.02))) / SR) * np.exp(-tt / 0.06)
    tick = filt(noise(n, 5), "hp", 4000) * np.exp(-tt / 0.006) * 0.4
    return soft_clip(thud * 1.1 + tick, 1.2) * 0.8


def whoosh(dur=0.5, up=True, seed=3, p0=-0.6, p1=0.6, level=0.7, lo=300, hi=6000):
    n = int(dur * SR)
    tt = np.linspace(0, 1, n)
    nz = noise(n, seed)
    sweep = (lo * (hi / lo) ** tt) if up else (hi * (lo / hi) ** tt)
    x = sweep_filt(nz, "bp", sweep, 1.6, block=128)
    env = np.sin(np.pi * tt) ** 1.5
    x = x * env * level
    pn = np.linspace(p0, p1, n)
    ang = (pn + 1) * np.pi / 4
    return np.stack([x * np.cos(ang), x * np.sin(ang)])


def pop(pitch=1.0):
    n = int(0.09 * SR)
    tt = t_axis(n)
    f = (480 + 500 * (1 - np.exp(-tt / 0.02))) * pitch
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.03) * 0.5


def click(pitch=1.0):
    n = int(0.05 * SR)
    tt = t_axis(n)
    return (filt(noise(n, 8), "hp", 2500) * np.exp(-tt / 0.003) * 0.5
            + np.sin(2 * np.pi * 1800 * pitch * tt) * np.exp(-tt / 0.008) * 0.35)


def tick(pitch=1.0):
    n = int(0.03 * SR)
    tt = t_axis(n)
    return (np.sin(2 * np.pi * 3200 * pitch * tt) * np.exp(-tt / 0.004) * 0.35
            + filt(noise(n, 9), "hp", 5000) * np.exp(-tt / 0.002) * 0.25)


def thunk(size=1.0):
    n = int(0.9 * SR)
    tt = t_axis(n)
    body = np.sin(2 * np.pi * np.cumsum(70 + 120 * np.exp(-tt / 0.035)) / SR) * np.exp(-tt / 0.16)
    slap = filt(noise(n, 12), "bp", 1800, 0.8) * np.exp(-tt / 0.018)
    paper = filt(noise(n, 13), "hp", 5000) * np.exp(-tt / 0.06) * 0.25
    return soft_clip((body * 1.1 + slap * 0.9 + paper) * size, 1.4) * 0.85


def key(seed=0, pitch=1.0):
    n = int(0.05 * SR)
    tt = t_axis(n)
    r = rng(seed)
    return (filt(noise(n, seed), "bp", 2200 * pitch * (0.8 + 0.4 * r.random()), 1.0) * np.exp(-tt / 0.006) * 0.6
            + np.sin(2 * np.pi * 180 * tt) * np.exp(-tt / 0.012) * 0.3)


def chime(base=1568.0):
    dur = 1.3
    n = int(dur * SR)
    tt = t_axis(n)
    out = np.zeros(n)
    for k, ratio in enumerate((1.0, 1.26, 1.68)):
        d = int(k * 0.07 * SR)
        f = base * ratio
        s = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * 2.01 * tt)) * np.exp(-tt / 0.35)
        out[d:] += s[: n - d] * 0.35
    return out


def horn(seed=0):
    parts = [(0.0, 0.12), (0.17, 0.12), (0.34, 0.34)]
    n = int(0.95 * SR)
    out = np.zeros(n)
    for start, ln in parts:
        m = int(ln * SR)
        x = saw(392.0, m) * 0.5 + saw(494.0, m) * 0.5 + pulse(196.0, m, 0.3) * 0.3
        x = filt(x, "lp", 2200)
        x *= adsr(m, 0.008, 0.03, 0.85, 0.03)
        i = int(start * SR)
        out[i:i + m] += x
    return soft_clip(out * 0.6, 1.2) * 0.7


def engine(dur=1.4):
    n = int(dur * SR)
    tt = t_axis(n)
    idle = saw(np.full(n, 52.0) * (1 + 0.03 * np.sin(2 * np.pi * 9 * tt)), n)
    idle = filt(idle, "lp", 220)
    rumble = filt(noise(n, 31), "lp", 140) * 0.8
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 18 * tt)
    env = np.minimum(1, np.minimum(tt / 0.12, (dur - tt) / 0.25))
    return (idle * 0.7 + rumble) * trem * env * 0.55


def flip():
    n = int(0.14 * SR)
    tt = np.linspace(0, 1, n)
    x = sweep_filt(noise(n, 41), "bp", 5000 * (600 / 5000) ** tt, 1.2, block=64) * (1 - tt) ** 1.5
    thud = np.sin(2 * np.pi * 140 * t_axis(n)) * np.exp(-t_axis(n) / 0.02) * 0.4
    return x * 0.9 + thud


def sparkle(dur=0.8, seed=51, count=14):
    n = int(dur * SR)
    out = np.zeros((2, n))
    r = rng(seed)
    for _ in range(count):
        t0 = r.random() * (dur - 0.15)
        f = 2600 + r.random() * 3800
        m = int(0.12 * SR)
        tt = t_axis(m)
        g = np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.03) * (0.15 + 0.2 * r.random())
        place(out, pan(g, r.uniform(-0.8, 0.8)), t0)
    return out


def swing(dur=0.55, p0=0.8, p1=-0.8):
    return whoosh(dur, up=False, seed=61, p0=p0, p1=p1, level=0.75, lo=250, hi=4200)


def boing():
    n = int(0.22 * SR)
    tt = t_axis(n)
    f = 260 + 700 * (1 - np.exp(-tt / 0.06))
    return pulse(f, n, 0.5) * np.exp(-tt / 0.08) * 0.35


def suck(dur=0.4):
    n = int(dur * SR)
    tt = np.linspace(0, 1, n)
    x = sweep_filt(noise(n, 71), "bp", 7000 * (250 / 7000) ** tt, 1.5, block=128) * tt ** 1.5
    return x * 0.8


def land():
    n = int(0.5 * SR)
    tt = t_axis(n)
    return soft_clip(np.sin(2 * np.pi * np.cumsum(60 + 80 * np.exp(-tt / 0.03)) / SR) * np.exp(-tt / 0.1)
                     + filt(noise(n, 81), "lp", 1200) * np.exp(-tt / 0.03) * 0.5, 1.3) * 0.8


def drop_block(pitch=1.0):
    n = int(0.25 * SR)
    tt = t_axis(n)
    return (np.sin(2 * np.pi * np.cumsum(150 * pitch * (1 + 0.8 * np.exp(-tt / 0.02))) / SR) * np.exp(-tt / 0.06) * 0.7
            + filt(noise(n, 91), "bp", 900, 1.0) * np.exp(-tt / 0.01) * 0.4)


def ignite():
    dur = 1.2
    n = int(dur * SR)
    tt = t_axis(n)
    out = np.zeros(n)
    for k, f0 in enumerate((392.0, 523.3, 659.3, 784.0, 1046.5)):
        d = int(k * 0.06 * SR)
        f = f0 * (1 + 0.5 * np.exp(-tt / 0.08))
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.4)
        out[d:] += s[: n - d] * 0.22
    swoosh = whoosh(0.7, up=True, seed=17, level=0.5, lo=200, hi=7000)
    out2 = np.stack([out, out])
    out2[:, : swoosh.shape[1]] += swoosh
    return out2


def portal_hum(dur=2.0):
    n = int(dur * SR)
    tt = t_axis(n)
    x = (np.sin(2 * np.pi * 110 * tt) + 0.5 * np.sin(2 * np.pi * 165.2 * tt) + 0.25 * np.sin(2 * np.pi * 220.7 * tt))
    x *= (0.7 + 0.3 * np.sin(2 * np.pi * 3 * tt)) * np.minimum(1, tt / 0.3) * np.minimum(1, (dur - tt) / 0.4)
    return x * 0.16


def bell(f=midi(81), dur=2.4):
    return _fm_bell(f, dur)


KINDS = {
    "hit": lambda p: hit(p.get("size", 1.0)),
    "clack": lambda p: clack(p.get("pitch", 1.0), p.get("seed", 0)),
    "word": lambda p: word(p.get("pitch", 1.0)),
    "whoosh": lambda p: whoosh(p.get("dur", 0.5), p.get("up", True), p.get("seed", 3), p.get("p0", -0.6), p.get("p1", 0.6), p.get("level", 0.7)),
    "pop": lambda p: pop(p.get("pitch", 1.0)),
    "click": lambda p: click(p.get("pitch", 1.0)),
    "tick": lambda p: tick(p.get("pitch", 1.0)),
    "thunk": lambda p: thunk(p.get("size", 1.0)),
    "key": lambda p: key(p.get("seed", 0), p.get("pitch", 1.0)),
    "chime": lambda p: chime(p.get("base", 1568.0)),
    "horn": lambda p: horn(),
    "engine": lambda p: engine(p.get("dur", 1.4)),
    "flip": lambda p: flip(),
    "sparkle": lambda p: sparkle(p.get("dur", 0.8), p.get("seed", 51), p.get("count", 14)),
    "swing": lambda p: swing(p.get("dur", 0.55), p.get("p0", 0.8), p.get("p1", -0.8)),
    "boing": lambda p: boing(),
    "suck": lambda p: suck(p.get("dur", 0.4)),
    "land": lambda p: land(),
    "drop": lambda p: drop_block(p.get("pitch", 1.0)),
    "ignite": lambda p: ignite(),
    "hum": lambda p: portal_hum(p.get("dur", 2.0)),
    "bell": lambda p: bell(),
}


def render_sfx(cues, total):
    N = int(total * SR)
    buf = np.zeros((2, N))
    for c in cues:
        kind = c["kind"]
        if kind not in KINDS:
            continue
        x = KINDS[kind](c)
        place(buf, x, c["t"], c.get("gain", 1.0) * 0.9)
    return buf
