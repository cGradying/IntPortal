#!/usr/bin/env python3
"""Objective audio checks (I cannot listen, so measure): kick onsets vs the 0.4 s grid, band balance, clipping."""
import json, os, sys
import numpy as np, soundfile as sf
from scipy import signal
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
x, sr = sf.read(os.path.join(ROOT, "audio", "master.wav"))
mono = x.mean(axis=1)
meta = json.load(open(os.path.join(ROOT, "audio", "audio_meta.json")))
kicks = np.array(meta["kicks"])
# low band energy envelope
sos = signal.butter(4, [40, 130], btype="band", fs=sr, output="sos")
low = signal.sosfiltfilt(sos, mono)
env = np.abs(signal.hilbert(low))
env = signal.savgol_filter(env, 401, 2)
pk, _ = signal.find_peaks(env, height=np.percentile(env, 92), distance=int(0.15 * sr))
pk_t = pk / sr
errs = []
for k in kicks:
    j = np.argmin(np.abs(pk_t - k))
    if abs(pk_t[j] - k) < 0.06:
        errs.append(pk_t[j] - k)
print(f"kicks expected {len(kicks)}, matched {len(errs)}; median offset {np.median(errs)*1000:.1f} ms, p95 |offset| {np.percentile(np.abs(errs),95)*1000:.1f} ms")
print("clipping samples:", int((np.abs(x) >= 0.999).sum()), " peak:", round(float(np.abs(x).max()), 3))
f, P = signal.welch(mono, sr, nperseg=8192)
def band(lo, hi): return P[(f >= lo) & (f < hi)].sum()
tot = P.sum()
for name, lo, hi in (("sub 20-60", 20, 60), ("bass 60-250", 60, 250), ("low-mid 250-1k", 250, 1000), ("mid 1-4k", 1000, 4000), ("high 4-10k", 4000, 10000), ("air 10k+", 10000, 22000)):
    print(f"{name:16s} {100*band(lo,hi)/tot:5.1f}%")
# per-bar loudness (rms dB)
bar = 1.6
print("per-bar RMS dBFS:", [round(20*np.log10(np.sqrt(np.mean(mono[int(i*bar*sr):int((i+1)*bar*sr)]**2))+1e-9),1) for i in range(20)])
