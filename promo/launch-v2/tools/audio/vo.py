"""Narrator (Kokoro, local ONNX) and Isko's chiptune 'talk' blips."""
import hashlib
import json
import os
import numpy as np
import soundfile as sf
from scipy import signal
from dsp import *  # noqa
from music import midi

MODEL = os.environ.get("KOKORO_MODEL", os.path.expanduser("~/models/kokoro/kokoro-v1.0.int8.onnx"))
VOICES = os.environ.get("KOKORO_VOICES", os.path.expanduser("~/models/kokoro/voices-v1.0.bin"))

_kokoro = None


def _get_kokoro():
    global _kokoro
    if _kokoro is None:
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro(MODEL, VOICES)
    return _kokoro


def synth_line(text, voice, speed, cache_dir):
    key = hashlib.sha1(f"{text}|{voice}|{speed}".encode()).hexdigest()[:12]
    path = os.path.join(cache_dir, f"vo_{key}.wav")
    if os.path.exists(path):
        x, sr = sf.read(path)
        return x, sr
    k = _get_kokoro()
    x, sr = k.create(text, voice=voice, speed=speed, lang="en-us")
    os.makedirs(cache_dir, exist_ok=True)
    sf.write(path, x, sr)
    return x, sr


def process_voice(x, sr):
    y = signal.resample_poly(x.astype(np.float64), SR, sr)
    y = filt(y, "hp", 110)
    # trim leading/trailing near-silence so cue times mean "first sound"
    thr = 0.02 * np.max(np.abs(y))
    idx = np.where(np.abs(y) > thr)[0]
    if len(idx):
        y = y[max(0, idx[0] - int(0.01 * SR)): idx[-1] + int(0.05 * SR)]
    y = soft_clip(y / (np.max(np.abs(y)) + 1e-9) * 0.95, 1.6)
    return y * db(-2.0)


def render_vo(lines, total, cache_dir):
    """lines: list of dict(id, t, text, voice, speed, gain). Returns stereo buf and durations."""
    N = int(total * SR)
    buf = np.zeros((2, N))
    ir = reverb_ir(1.1, seed=8, damp=5000)
    durs = {}
    for ln in lines:
        x, sr = synth_line(ln["text"], ln.get("voice", "af_heart"), ln.get("speed", 1.05), cache_dir)
        y = process_voice(x, sr)
        durs[ln["id"]] = len(y) / SR
        wet = apply_reverb(y, ir, 0.10)
        st = np.stack([y, y]) + wet[:, : len(y)] if wet.shape[1] >= len(y) else np.stack([y, y])
        place(buf, st, ln["t"], ln.get("gain", 1.0))
    return buf, durs


PENTA = [0, 2, 4, 7, 9]


def blip_line(text, t0, gain=1.0, base=72, speed=1.0):
    """Returns (list of (t, freq) onsets, stereo array segment placed by caller at t0)."""
    onsets = []
    t = 0.0
    for ch in text:
        c = ch.lower()
        if c.isalpha():
            v = ord(c) - 97
            note = base + PENTA[v % 5] + 12 * ((v // 5) % 2)
            onsets.append((t, midi(note)))
            t += 0.062 / speed
        elif c in " ":
            t += 0.045 / speed
        elif c in ",;":
            t += 0.11 / speed
        else:
            t += 0.16 / speed
    dur = t + 0.15
    n = int(dur * SR)
    seg = np.zeros(n)
    for (to, f) in onsets:
        m = int(0.052 * SR)
        w = pulse(np.full(m, f), m, 0.5) * 0.6 + pulse(np.full(m, f * 2.0), m, 0.25) * 0.25
        w *= adsr(m, 0.002, 0.02, 0.6, 0.015)
        i = int(to * SR)
        seg[i:i + m] += w[: max(0, min(m, n - i))]
    seg = filt(seg, "lp", 6500)
    st = pan(seg * 0.35 * gain, 0.0)
    return onsets, st


def render_blips(items, total):
    N = int(total * SR)
    buf = np.zeros((2, N))
    info = []
    for it in items:
        onsets, st = blip_line(it["text"], it["t"], it.get("gain", 1.0), it.get("base", 72), it.get("speed", 1.0))
        place(buf, st, it["t"])
        info.append({"id": it["id"], "t": it["t"], "text": it["text"],
                     "chars": [round(o[0], 3) for o in onsets], "dur": st.shape[1] / SR})
    return buf, info
