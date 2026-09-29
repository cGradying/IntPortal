#!/usr/bin/env python3
"""Render the trailer soundtrack: music + SFX + narrator + Isko blips -> audio/master.wav

Usage:  python tools/audio/build_audio.py     (numpy, scipy, soundfile, kokoro-onnx; ffmpeg on PATH)
Reads cues/cues.json (run tools/cues_def.py first). Deterministic; VO lines are cached."""
import json
import os
import subprocess
import sys

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dsp import *  # noqa
import music
import sfx
import vo as vomod

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "audio")
os.makedirs(os.path.join(OUT, "stems"), exist_ok=True)
os.makedirs(os.path.join(OUT, "vo"), exist_ok=True)

doc = json.load(open(os.path.join(ROOT, "cues", "cues.json")))
TOTAL = doc["duration"]
N = int(TOTAL * SR)


def fit(x):
    if x.shape[1] >= N:
        return x[:, :N]
    return np.pad(x, ((0, 0), (0, N - x.shape[1])))


def env_follow(mono, win_hz=441, attack=0.03, release=0.35):
    """Cheap envelope follower at reduced rate, returned at full rate (length len(mono))."""
    hop = SR // win_hz
    m = len(mono) // hop
    a = np.abs(mono[: m * hop]).reshape(m, hop).max(axis=1)
    out = np.zeros(m)
    ca, cr = np.exp(-1 / (attack * win_hz)), np.exp(-1 / (release * win_hz))
    prev = 0.0
    for i, v in enumerate(a):
        c = ca if v > prev else cr
        prev = c * prev + (1 - c) * v
        out[i] = prev
    xs = np.arange(len(mono)) / hop
    return np.interp(xs, np.arange(m), out)


print("music ...")
m = music.render_music()
drums, bass, harm, fxb = fit(m["drums"]), fit(m["bass"]), fit(m["harm"]), fit(m["fx"])
kick_duck = music.kick_duck(m["kicks"], N)

print("sfx ...")
sfx_bus = sfx.render_sfx(doc["cues"], TOTAL)

print("voice ...")
vo_bus, durs = vomod.render_vo(doc["vo"], TOTAL, os.path.join(OUT, "vo"))
blip_bus, blip_info = vomod.render_blips(doc["blips"], TOTAL)
vo_mono = vo_bus.mean(axis=0)
vo_env = env_follow(vo_mono)
vo_env = np.clip(vo_env / (np.max(vo_env) * 0.35 + 1e-9), 0, 1)
music_duck_vo = 1.0 - 0.42 * vo_env          # ~ -4.7 dB under narration

# ---- mix ----
music_bus = (drums * 0.9 + bass * kick_duck * 0.75 + harm * (0.6 + 0.4 * kick_duck) * 1.15 + fxb * 0.9)
music_bus *= music_duck_vo
sfx_gain = 0.85
master = music_bus + sfx_bus * sfx_gain * (1.0 - 0.25 * vo_env) + vo_bus * 1.35 + blip_bus * 0.9

master = np.stack([filt(ch, "hp", 30) for ch in master])
# gentle fade in/out
fade_out = int(0.9 * SR)
master[:, -fade_out:] *= np.linspace(1, 0, fade_out)
master[:, :int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))

# glue: soft clip then peak-normalise before loudnorm
master = soft_clip(master / (np.max(np.abs(master)) + 1e-9) * 1.1, 1.0)
raw = os.path.join(OUT, "master_raw.wav")
sf.write(raw, master.T.astype(np.float32), SR, subtype="FLOAT")
for name, bus in (("drums", drums), ("bass", bass), ("harm", harm), ("fx", fxb), ("sfx", sfx_bus), ("vo", vo_bus), ("blips", blip_bus)):
    sf.write(os.path.join(OUT, "stems", f"{name}.wav"), bus.T.astype(np.float32), SR, subtype="PCM_16")

# ---- loudness: two-pass loudnorm to -14 LUFS / -1 dBTP ----
def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

p1 = run(["ffmpeg", "-hide_banner", "-nostats", "-i", raw, "-af", "loudnorm=I=-14:TP=-1.0:LRA=9:print_format=json", "-f", "null", "-"])
txt = p1.stderr
j = json.loads(txt[txt.rindex("{"): txt.rindex("}") + 1])
print("measured:", {k: j[k] for k in ("input_i", "input_tp", "input_lra")})
af = (f"loudnorm=I=-14:TP=-1.0:LRA=9:measured_I={j['input_i']}:measured_TP={j['input_tp']}:"
      f"measured_LRA={j['input_lra']}:measured_thresh={j['input_thresh']}:offset={j['target_offset']}:linear=true")
final = os.path.join(OUT, "master.wav")
p2 = run(["ffmpeg", "-y", "-hide_banner", "-nostats", "-i", raw, "-af", af, "-ar", "48000", "-c:a", "pcm_s16le", final])
if p2.returncode != 0:
    print(p2.stderr[-800:])
    sys.exit(1)
p3 = run(["ffmpeg", "-hide_banner", "-nostats", "-i", final, "-af", "loudnorm=I=-14:TP=-1.0:print_format=json", "-f", "null", "-"])
t3 = p3.stderr
j3 = json.loads(t3[t3.rindex("{"): t3.rindex("}") + 1])
print("final:", {k: j3[k] for k in ("input_i", "input_tp", "input_lra")})

json.dump({"vo_durations": durs, "blips": blip_info, "kicks": [round(float(k), 4) for k in m["kicks"]],
           "loudness": {k: j3[k] for k in ("input_i", "input_tp", "input_lra")}},
          open(os.path.join(OUT, "audio_meta.json"), "w"), indent=1)
print("wrote", final)
