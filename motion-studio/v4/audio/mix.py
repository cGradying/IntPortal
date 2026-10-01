"""v4 mix: music + girl VO + UI SFX on every cursor/beat event -> audio/mix.wav

    python3 audio/mix.py [temp|el]

`temp` uses music_temp.wav + vo/temp (stand-ins); `el` uses ElevenLabs
music_el.mp3 (time-fitted to the film) + vo/el. VO ducks the music; the
sum is gained to -14 LUFS and limited to <= -1 dBTP (4x oversampled).
"""
import json, os, subprocess, sys
import numpy as np, soundfile as sf, pyloudnorm as pyln
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 48000
FRAMES, FPS, NB = 5428, 60, 196
DUR = FRAMES / FPS
N = int(round(DUR * SR))
MODE = sys.argv[1] if len(sys.argv) > 1 else "temp"
cues = json.load(open(os.path.join(HERE, "cues.json")))
GRID = cues["beats"]
rng = np.random.default_rng(7)


def B(b):
    i = int(np.floor(b))
    return GRID[i] + (GRID[i + 1] - GRID[i]) * (b - i)


def load(path):
    if path.endswith(".mp3"):
        wav = path[:-4] + ".dec.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ar", str(SR), "-ac", "2", wav], check=True)
        path = wav
    a, sr = sf.read(path, always_2d=True)
    assert sr == SR, path
    return a if a.shape[1] == 2 else np.repeat(a, 2, axis=1)


def filt(x, kind, f, order=2):
    return sosfilt(butter(order, f, btype=kind, fs=SR, output="sos"), x, axis=0)


# ---------------------------------------------------------------- music
if MODE == "el":
    raw = os.path.join(HERE, "music_el.mp3")
    fit = os.path.join(HERE, "music_el_fit.wav")
    d = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", raw]))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", f"atempo={d / DUR:.6f}", "-ar", str(SR), "-ac", "2", fit], check=True)
    music = load(fit)
    # beats.py measures where the track's downbeat sits; the file loops, so roll it onto t = 0
    off = json.load(open(os.path.join(HERE, "..", "beats.json"))).get("offset", 0.0)
    music = np.roll(music, -int(round(off * SR)), axis=0)
else:
    music = load(os.path.join(HERE, "music_temp.wav"))
music = np.pad(music, ((0, max(0, N - len(music))), (0, 0)))[:N]

# ---------------------------------------------------------------- VO
lines = json.load(open(os.path.join(HERE, "vo.json")))["lines"]
vo = np.zeros((N, 2))
for l in lines:
    p = os.path.join(HERE, "vo", "el" if MODE == "el" else "temp", f"{l['id']}.{'mp3' if MODE == 'el' else 'wav'}")
    a = load(p)
    a = filt(a, "high", 90)
    a = a + filt(a, "band", [2500, 6000]) * 0.25  # a little presence
    # gentle leveling: each line to the same loudness
    m = pyln.Meter(SR)
    a *= 10 ** ((-20 - m.integrated_loudness(a)) / 20) if len(a) > SR * 0.4 else 1
    i = int(B(l["beat"]) * SR)
    j = min(N, i + len(a))
    vo[i:j] += a[: j - i]

# duck: smoothed VO envelope pulls the music down up to 7 dB
env = np.abs(vo).max(axis=1)
k_att, k_rel = np.exp(-1 / (0.03 * SR)), np.exp(-1 / (0.3 * SR))
e = np.zeros(N)
v = 0.0
for n_ in range(0, N, 48):  # 1 ms hops
    x = env[n_:n_ + 48].max()
    v = x + (v - x) * (k_att ** 48 if x > v else k_rel ** 48)
    e[n_:n_ + 48] = v
duck = 10 ** (-7 * np.clip(e / 0.05, 0, 1) / 20)


# ---------------------------------------------------------------- SFX
def tick(f=3200, d=0.025, g=1.0):
    n = int(d * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) * 0.5 + filt(rng.standard_normal(n), "band", [f * 0.6, min(f * 1.8, 20000)]) * 0.5) * np.exp(-t * 180) * g


def click(g=1.0):
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    down = tick(3400, 0.03, 1.0)
    body = np.sin(2 * np.pi * 170 * t) * np.exp(-t * 60) * 0.5
    out = body.copy()
    out[: len(down)] += down
    up = tick(4200, 0.02, 0.45)
    o = int(0.09 * SR)
    out[o:o + len(up)] += up[: n - o]
    return out * g


def whoosh(d=0.28, g=1.0):
    n = int(d * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    lo = filt(x, "band", [300, 1400]) * np.sin(np.pi * t / d) ** 2
    hi = filt(x, "band", [1800, 6000]) * np.sin(np.pi * np.clip(t / d * 1.3, 0, 1)) ** 4 * 0.4
    return (lo + hi) * 0.6 * g


def stamp(g=1.0):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 80 * t) * np.exp(-t * 18) + filt(rng.standard_normal(n), "band", [400, 2500]) * np.exp(-t * 40) * 0.6) * g


sfx = np.zeros((N, 2))


def put(sig, t, g=1.0, pan=0.0):
    i = int(t * SR)
    j = min(N, i + len(sig))
    if i < 0 or j <= i:
        return
    sfx[i:j, 0] += sig[: j - i] * g * np.sqrt(0.5 * (1 - pan))
    sfx[i:j, 1] += sig[: j - i] * g * np.sqrt(0.5 * (1 + pan))


for c in cues["clicks"]:
    put(click(), c["t"] - 0.04, 0.5)
for h in cues["holds"]:
    put(click(0.7), h["ta"] - 0.04, 0.35)
    put(tick(2600, 0.02), h["tz"], 0.3)
TYPE = ("type", "you@", "school", ".edu")
MORPH = ("->", "grows", "morph", "expands", "becomes", "shrinks", "folds", "deal", "page", "flip", "dive", "scatter")
for ev in cues["events"]:
    s, t = ev["e"].lower(), ev["t"]
    pan = float(np.sin(ev["b"] * 1.7)) * 0.3
    if s.startswith("click"):
        continue
    if any(k in s for k in TYPE):
        for q in range(4):
            put(tick(2200 + 300 * (q % 2), 0.018), t + q * 0.045, 0.28, pan)
    elif "stamp" in s:
        put(stamp(), t, 0.5)
    elif "toggle" in s:
        put(tick(2000, 0.02), t, 0.35); put(tick(2600, 0.02), t + 0.06, 0.3)
    elif any(k in s for k in MORPH):
        put(whoosh(), t - 0.03, 0.22, pan); put(tick(1800, 0.02), t, 0.2, pan)
    elif any(ch.isdigit() for ch in s):
        put(tick(3800, 0.02), t, 0.22, pan)
    else:
        put(tick(2400 + 400 * (ev["b"] % 3), 0.02), t, 0.16, pan)

# ---------------------------------------------------------------- sum, loudness, limiter
mix = music * duck[:, None] * 0.9 + vo * 1.0 + sfx * 0.8
raw = os.path.join(HERE, "mix_raw.wav")
sf.write(raw, mix.astype(np.float32), SR)
meter = pyln.Meter(SR)
gain = -14.0 - meter.integrated_loudness(mix)
out = os.path.join(HERE, "mix.wav")
for _ in range(4):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af",
                    f"volume={gain:.3f}dB,aresample=192000,alimiter=limit=0.85:attack=1:release=60:level=disabled,aresample={SR}",
                    "-c:a", "pcm_f32le", out], check=True)
    y, _ = sf.read(out)
    lu = meter.integrated_loudness(y)
    if abs(lu + 14) < 0.15:
        break
    gain += -14 - lu
tp = subprocess.run(["ffmpeg", "-hide_banner", "-i", out, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
print(MODE, f"LUFS {lu:.2f}", [l.strip() for l in tp.splitlines() if "Peak:" in l][-1:])
