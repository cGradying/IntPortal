"""Measure the beat grid of the ElevenLabs track and write beats.json.

    python3 audio/beats.py audio/music_el_fit.wav

The track is first time-fitted to the film (audio/mix.py el does that). Each
nominal beat snaps to the strongest onset within 30 ms; where nothing is
close (breaks, held chords) it stays on the nominal grid. Beat 0 and beat
196 are pinned to 0 and the film length so the loop length never changes.
Then re-render the clips (scripts/clips.mjs) and the film.
"""
import json, os, sys
import numpy as np, librosa

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES, FPS, NB = 5428, 60, 196
DUR = FRAMES / FPS
NOM = DUR / NB

y, sr = librosa.load(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "music_el_fit.wav"), sr=22050, mono=True)
hop = 128
onset = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
times = librosa.frames_to_time(np.arange(len(onset)), sr=sr, hop_length=hop)
# global offset: the shift of the nominal grid that best lines up with onsets
shifts = np.linspace(-NOM / 2, NOM / 2, 81)
score = [np.interp((np.arange(NB) * NOM + s) % DUR, times, onset).sum() for s in shifts]
off = shifts[int(np.argmax(score))]
beats = []
for b in range(NB + 1):
    t0 = b * NOM + off
    win = (times > t0 - 0.03) & (times < t0 + 0.03)
    t = times[win][np.argmax(onset[win])] if win.any() and onset[win].max() > np.median(onset) * 2 else t0
    beats.append(float(t))
beats = list(np.array(beats) - beats[0])  # beat 0 at t = 0
beats[-1] = DUR
drift = max(abs(beats[b] - b * NOM) for b in range(NB + 1))
json.dump({"bpm": 60 / NOM, "offset": float(off), "beats": beats}, open(os.path.join(HERE, "..", "beats.json"), "w"))
print(f"offset {off * 1000:.1f} ms, max drift from nominal {drift * 1000:.1f} ms")
