"""Small numpy DSP kit for the IntPortal trailer soundtrack. Deterministic (seeded)."""
import numpy as np
from scipy import signal

SR = 44100


def rng(seed):
    return np.random.default_rng(seed)


def t_axis(n):
    return np.arange(n) / SR


def db(x):
    return 10 ** (x / 20.0)


# ---------- oscillators (band-limited with polyBLEP) ----------
def _polyblep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m] if np.ndim(dt) else t[m] / dt
    out[m] = x + x - x * x - 1.0
    m2 = t > 1.0 - dt
    x2 = (t[m2] - 1.0) / (dt[m2] if np.ndim(dt) else dt)
    out[m2] = x2 * x2 + x2 + x2 + 1.0
    return out


def phase_of(freq, n=None):
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, dtype=float)
    ph = np.cumsum(f / SR)
    return ph % 1.0, f / SR


def saw(freq, n=None):
    ph, dt = phase_of(freq, n)
    return 2.0 * ph - 1.0 - _polyblep(ph, dt)


def pulse(freq, n=None, pw=0.5):
    ph, dt = phase_of(freq, n)
    pw_arr = np.full_like(ph, pw) if np.isscalar(pw) else np.asarray(pw)
    y = np.where(ph < pw_arr, 1.0, -1.0)
    y = y + _polyblep(ph, dt) - _polyblep((ph - pw_arr) % 1.0, dt)
    return y


def sine(freq, n=None):
    ph, _ = phase_of(freq, n)
    return np.sin(2 * np.pi * ph)


def tri(freq, n=None):
    ph, _ = phase_of(freq, n)
    return 2.0 * np.abs(2.0 * ph - 1.0) - 1.0


def noise(n, seed=0):
    return rng(seed).standard_normal(n)


# ---------- envelopes ----------
def adsr(n, a=0.005, d=0.05, s=0.7, r=0.05):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    env = np.concatenate([
        np.linspace(0, 1, max(a_n, 1), endpoint=False),
        np.linspace(1, s, max(d_n, 1), endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env[:n]


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


# ---------- filters ----------
def biquad(kind, fc, q=0.707, fs=SR):
    w0 = 2 * np.pi * fc / fs
    alpha = np.sin(w0) / (2 * q)
    cw = np.cos(w0)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    elif kind == "bp":
        b = [alpha, 0, -alpha]
    elif kind == "notch":
        b = [1, -2 * cw, 1]
    else:
        raise ValueError(kind)
    a = [1 + alpha, -2 * cw, 1 - alpha]
    return np.array(b) / a[0], np.array([1.0, a[1] / a[0], a[2] / a[0]])


def filt(x, kind, fc, q=0.707):
    b, a = biquad(kind, min(fc, SR * 0.45), q)
    return signal.lfilter(b, a, x)


def sweep_filt(x, kind, fc_curve, q=0.9, block=256):
    """Time-varying biquad: fc_curve is an array (same length as x)."""
    y = np.zeros_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        fc = float(np.clip(fc_curve[min(i + block // 2, len(x) - 1)], 20, SR * 0.45))
        b, a = biquad(kind, fc, q)
        seg, zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
        y[i:i + block] = seg
    return y


# ---------- effects ----------
def reverb_ir(seconds=1.8, seed=1, damp=4000.0, pre=0.012):
    n = int(seconds * SR)
    r = rng(seed)
    ir = np.stack([r.standard_normal(n), r.standard_normal(n)])
    env = np.exp(-np.arange(n) / (0.28 * seconds * SR))
    ir *= env
    ir = np.stack([filt(ch, "lp", damp) for ch in ir])
    pad = int(pre * SR)
    ir = np.pad(ir, ((0, 0), (pad, 0)))
    ir /= np.sqrt((ir ** 2).sum(axis=1, keepdims=True)) + 1e-9
    return ir


def apply_reverb(x_mono, ir, mix=1.0):
    l = signal.fftconvolve(x_mono, ir[0])[: len(x_mono)]
    r = signal.fftconvolve(x_mono, ir[1])[: len(x_mono)]
    return np.stack([l, r]) * mix


def ping_delay(x, time_l, time_r, fb=0.35, mix=0.4):
    n = len(x)
    out = np.zeros((2, n))
    for ch, tm in enumerate((time_l, time_r)):
        d = int(tm * SR)
        y = np.zeros(n)
        tap = x.copy()
        gain = 1.0
        pos = d
        while pos < n and gain > 0.02:
            y[pos:] += tap[: n - pos] * gain
            gain *= fb
            pos += d
        out[ch] = y * mix
    return out


def pan(x, p):
    """p in [-1, 1]; returns (2, n)."""
    ang = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(ang), x * np.sin(ang)])


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive) if drive > 0 else x


def place(buf, x, t0, gain=1.0):
    """Add mono (n,) or stereo (2,n) x into stereo buf (2,N) at time t0."""
    i0 = int(round(t0 * SR))
    if x.ndim == 1:
        x = np.stack([x, x])
    n = x.shape[1]
    if i0 >= buf.shape[1]:
        return
    i1 = min(buf.shape[1], i0 + n)
    if i0 < 0:
        x = x[:, -i0:]
        i0 = 0
        i1 = min(buf.shape[1], i0 + x.shape[1])
    buf[:, i0:i1] += x[:, : i1 - i0] * gain


def rms_env(x_mono, win=0.02):
    w = int(win * SR)
    e = np.sqrt(np.convolve(x_mono ** 2, np.ones(w) / w, mode="same"))
    return e


def smooth_env(env, attack=0.02, release=0.25):
    """One-pole follower with separate attack/release (samples)."""
    a = np.exp(-1.0 / (attack * SR))
    r = np.exp(-1.0 / (release * SR))
    y = np.zeros_like(env)
    prev = 0.0
    for i, v in enumerate(env):
        coef = a if v > prev else r
        prev = coef * prev + (1 - coef) * v
        y[i] = prev
    return y
