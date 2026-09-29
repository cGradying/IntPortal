"""Measure the beat grid of music.wav with librosa -> ../beats.json.

The film snaps every hit to these measured times. We also report drift
against the nominal grid so a mis-locked tracker is caught.
"""
import json, os
import numpy as np, librosa

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, "..", "timeline.json")))
y, sr = librosa.load(os.path.join(HERE, "music.wav"), sr=22050, mono=True)
tempo, frames = librosa.beat.beat_track(y=y, sr=sr, start_bpm=TL["bpm"], tightness=400, units="frames")
onset_env = librosa.onset.onset_strength(y=y, sr=sr)
times = librosa.frames_to_time(frames, sr=sr)
beat = 60.0 / TL["bpm"]
total = TL["bars"] * 4
# phase-lock: nominal index for each measured beat
idx = np.round(times / beat).astype(int)
grid = []
for n in range(total + 1):
    hit = times[idx == n]
    grid.append(float(hit[0]) if len(hit) else float(n * beat))
grid = np.array(grid)
# refine: snap each tracked beat to the nearest transient (fine hop, backtracked)
y48, sr48 = librosa.load(os.path.join(HERE, "music.wav"), sr=48000, mono=True)
hop = 64
env = librosa.onset.onset_strength(y=y48, sr=sr48, hop_length=hop)
on = librosa.onset.onset_detect(onset_envelope=env, sr=sr48, hop_length=hop, backtrack=True, units="time")
for n, t in enumerate(grid):
    near = on[np.abs(on - t) < 0.07]
    if len(near):
        grid[n] = near[np.argmin(np.abs(near - n * beat))]
drift = grid - np.arange(total + 1) * beat
out = {
    "bpm_measured": float(np.atleast_1d(tempo)[0]),
    "bpm": TL["bpm"],
    "beats": [round(float(t), 4) for t in grid],
    "matched": int(sum(1 for n in range(total + 1) if (idx == n).any())),
    "max_abs_drift_ms": round(float(np.abs(drift).max() * 1000), 1),
    "median_drift_ms": round(float(np.median(drift) * 1000), 1),
}
json.dump(out, open(os.path.join(HERE, "..", "beats.json"), "w"), indent=1)
print({k: v for k, v in out.items() if k != "beats"})
