#!/usr/bin/env python3
"""Single source of truth for the trailer's clock.

150 BPM: beat = 0.4 s, bar = 1.6 s, 20 bars = 32 s. Audio (tools/audio/build_audio.py)
and the composition (composition/assets/cues.js) both read the output of this file,
so a visual hit and its sound can never drift apart.

Run:  python3 tools/cues_def.py   ->  cues/cues.json  +  composition/assets/cues.js
"""
import json
import os

BPM = 150
BEAT = 60.0 / BPM
BAR = BEAT * 4
DURATION = 32.0
FPS = 60


def bt(beats):
    return round(beats * BEAT, 4)


SCENES = [
    # id, first bar (1-indexed), bars
    ("void",   1, 2),
    ("isko",   3, 2),
    ("today",  5, 2),
    ("sync",   7, 2),
    ("mac",    9, 2),
    ("grades", 11, 2),
    ("study",  13, 2),
    ("rooms",  15, 2),
    ("campus", 17, 2),
    ("end",    19, 2),
]

scenes = [{"id": i, "start": round((b - 1) * BAR, 4), "end": round((b - 1 + n) * BAR, 4)} for i, b, n in SCENES]

cues = []


def cue(id, t, kind, gain=1.0, **kw):
    d = {"id": id, "t": round(t, 4), "kind": kind, "gain": gain}
    d.update(kw)
    cues.append(d)


# ---------------------------------------------------------------- 1. void + portal (0 - 3.2)
cue("hit0", 0.0, "hit", 1.0, size=0.9)
BLOCK_T0, BLOCK_DT = 0.30, 0.048
for i in range(24):
    cue(f"blk{i}", BLOCK_T0 + i * BLOCK_DT, "clack", 0.5, pitch=0.8 + 0.5 * ((i * 7) % 6) / 5.0, seed=i)
cue("word1", bt(1), "word", 0.9, pitch=1.0)          # YOUR CAMPUS.
cue("ignite", bt(4), "ignite", 0.9)                  # portal lights
cue("word2", bt(3), "word", 0.9, pitch=1.25)         # IN YOUR POCKET.
cue("run_in", bt(6), "whoosh", 0.55, dur=0.7, p0=-0.9, p1=0.1, level=0.6)   # Isko runs in
# ---------------------------------------------------------------- 2. meet Isko (3.2 - 6.4)
cue("land", bt(8), "land", 0.9)
cue("bubble", bt(10), "pop", 0.8, pitch=1.2)
cue("boing", bt(14), "boing", 0.8)
cue("dive_whoosh", bt(13.5), "whoosh", 0.8, dur=0.9, up=True, p0=-0.3, p1=0.3, level=0.9)
cue("suck", bt(15) - 0.05, "suck", 0.7, dur=0.45)
cue("drop_hit", bt(16), "hit", 1.15, size=1.15)      # THE DROP + whiteout
cue("drop_sparkle", bt(16), "sparkle", 0.6, dur=1.0, seed=52)
# ---------------------------------------------------------------- 3. iPhone Today (6.4 - 9.6)
cue("phone_in", bt(16.2), "swing", 0.8, dur=0.6, p0=-0.8, p1=0.7)
for k, tb in enumerate((17.0, 17.5, 18.0)):
    cue(f"layer{k}", bt(tb), "tick", 0.8, pitch=1.0 + 0.2 * k)
cue("island", bt(18), "pop", 0.9, pitch=0.9)
cue("hero_tick1", bt(19), "tick", 0.6, pitch=1.3)
cue("coach", bt(20), "pop", 0.8, pitch=1.1)
cue("tab_hop", bt(21.5), "click", 0.7)
# ---------------------------------------------------------------- 4. sync jeepney (9.6 - 12.8)
cue("sync_cut", bt(24) - 0.05, "whoosh", 0.6, dur=0.35, up=True, level=0.6)
cue("pull", bt(24.5), "tick", 0.8, pitch=0.8)
cue("release", bt(25), "click", 0.9, pitch=0.9)
cue("horn", bt(26), "horn", 0.6)
cue("engine", bt(26), "engine", 0.55, dur=1.5)
cue("arrived", bt(29), "chime", 0.9)
for k, tb in enumerate((29.5, 30.0, 30.5, 31.0)):
    cue(f"sched{k}", bt(tb), "pop", 0.7, pitch=1.0 + 0.12 * k)
# ---------------------------------------------------------------- 5. Mac round trip (12.8 - 16.0)
cue("mac_swing", bt(32) - 0.02, "swing", 0.9, dur=0.6)
cue("stamp_online", bt(33), "thunk", 1.0, size=1.0)
cue("panel", bt(33.5), "pop", 0.8, pitch=1.0)          # assistant panel lifts off the window
for k in range(16):
    cue(f"key{k}", bt(34) + k * 0.05, "key", 0.55, seed=k, pitch=0.9 + 0.2 * ((k * 5) % 4) / 3.0)
cue("send", bt(36), "click", 0.9, pitch=1.2)
for k in range(10):
    cue(f"ans{k}", bt(37) + k * 0.11, "tick", 0.32, pitch=0.9 + 0.05 * (k % 4))
cue("local_stamp", bt(38), "thunk", 0.9, size=0.9)      # LOCAL BY DEFAULT
cue("chips", bt(39), "chime", 0.7, base=1318.5)
# ---------------------------------------------------------------- 6. Grades (16.0 - 19.2)
cue("grades_swing", bt(40) - 0.02, "swing", 0.8, dur=0.55, p0=-0.8, p1=0.8)
for k, tb in enumerate((41, 42, 43, 44)):
    cue(f"gstamp{k}", bt(tb), "thunk", 0.85, size=0.85)
cue("best", bt(45), "thunk", 1.05, size=1.1)
cue("confetti", bt(45), "sparkle", 0.9, dur=1.1, seed=53, count=24)
cue("cheer", bt(46), "boing", 0.7)
# ---------------------------------------------------------------- 7. Study (19.2 - 22.4)
cue("study_cut", bt(48) - 0.02, "whoosh", 0.55, dur=0.4, up=True, level=0.6)
cue("flip", bt(50), "flip", 0.9)
cue("rate", bt(52), "click", 0.9, pitch=1.1)
cue("streak", bt(52.5), "chime", 0.7, base=1760.0)
for k in range(6):
    cue(f"tower{k}", bt(53) + k * 0.16, "drop", 0.7, pitch=0.8 + 0.12 * k)
cue("study_suck", bt(54.5), "suck", 0.7, dur=0.55)
# ---------------------------------------------------------------- 8. Rooms (22.4 - 25.6)
cue("final_drop", bt(56), "hit", 1.2, size=1.2)
for k in range(8):
    cue(f"room{k}", bt(56 + k), "thunk", 0.55, size=0.6)
    cue(f"room_sw{k}", bt(56 + k) - 0.03, "whoosh", 0.35, dur=0.22, up=(k % 2 == 0), level=0.5, p0=-0.5, p1=0.5)
# ---------------------------------------------------------------- 9. every campus (25.6 - 28.8)
cue("pullback", bt(64), "whoosh", 0.7, dur=1.0, up=False, level=0.7)
cue("hub_hum", bt(66), "hum", 0.6, dur=2.4)
for k, tb in enumerate((68, 69, 70)):
    cue(f"flicker{k}", bt(tb), "tick", 0.7, pitch=0.7 + 0.2 * k)
cue("campus_riser_whoosh", bt(70.5), "whoosh", 0.6, dur=0.9, up=True, level=0.7)
# ---------------------------------------------------------------- 10. end card (28.8 - 32.0)
cue("end_hit", bt(72), "hit", 1.05, size=1.05)
for i in range(18):
    cue(f"wm{i}", bt(72) + 0.08 + i * 0.05, "clack", 0.45, pitch=1.0 + 0.4 * ((i * 5) % 7) / 6.0, seed=100 + i)
cue("wordmark", bt(74), "sparkle", 0.6, dur=0.9, seed=54, count=16)
cue("btn", bt(77), "pop", 0.9, pitch=1.3)
cue("final_bell", bt(76), "bell", 0.8)
cue("url", bt(77.5), "click", 0.7)

# ---------------------------------------------------------------- voice (narrator via Kokoro)
VOICE = "af_heart"
vo = [
    {"id": "v1", "t": 0.30, "text": "Your campus. In your pocket."},
    {"id": "v2", "t": 3.25, "text": "Meet Isko."},
    {"id": "v3", "t": 6.75, "text": "Always know what's next."},
    # "Pull. Sync. Done." is three hits so each word lands on its own visual beat (release / horn / arrival chime)
    {"id": "v4a", "t": 9.98, "text": "Pull."},
    {"id": "v4b", "t": 10.42, "text": "Sync."},
    {"id": "v4c", "t": 11.58, "text": "Done."},
    {"id": "v5a", "t": 12.95, "text": "Ask Intassis."},   # spelled so the TTS stresses in-TASS-iss
    {"id": "v5b", "t": 15.12, "text": "Local by default."},
    {"id": "v6", "t": 16.3, "text": "Every grade, stamped."},
    {"id": "v7", "t": 19.5, "text": "Study smarter. Keep the streak."},
    {"id": "v8", "t": 22.55, "text": "Pick your room."},
    {"id": "v9", "t": 25.9, "text": "Santa Mesa first. Every campus next."},
    {"id": "v10", "t": 30.05, "text": "Int Portal. Step through."},
]
for v in vo:
    v.update({"voice": VOICE, "speed": 1.06, "gain": 1.0})

# Isko's talk blips (text shown in his speech bubbles)
blips = [
    {"id": "b1", "t": bt(10), "text": "Hi, I'm Isko!", "base": 72},
    {"id": "b2", "t": bt(45) + 0.15, "text": "Personal best!", "base": 74},
    {"id": "b3", "t": 31.35, "text": "Tara na!", "base": 72},
]

doc = {
    "bpm": BPM, "beat": BEAT, "bar": BAR, "duration": DURATION, "fps": FPS,
    "scenes": scenes, "cues": sorted(cues, key=lambda c: c["t"]), "vo": vo, "blips": blips,
}

if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    os.makedirs(os.path.join(root, "cues"), exist_ok=True)
    with open(os.path.join(root, "cues", "cues.json"), "w") as f:
        json.dump(doc, f, indent=1)
    os.makedirs(os.path.join(root, "composition", "assets"), exist_ok=True)
    with open(os.path.join(root, "composition", "assets", "cues.js"), "w") as f:
        f.write("window.CUES = " + json.dumps(doc) + ";\n")
    print(f"{len(cues)} cues, {len(vo)} voice lines, {len(blips)} blip lines, scenes={len(scenes)}")
