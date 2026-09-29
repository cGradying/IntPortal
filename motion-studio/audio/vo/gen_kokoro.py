"""VO: render every script line with Kokoro-82M (local, offline).
Writes audio/vo/takes/<id>_<who>.wav at 48 kHz."""
import json, os
import numpy as np, soundfile as sf
from kokoro_onnx import Kokoro
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, "script.json")))
K = os.path.join(HERE, "..", "kokoro")
k = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))
os.makedirs(os.path.join(HERE, "takes"), exist_ok=True)
for line in S["lines"]:
    for who in line["who"]:
        v = S["voices"][who]
        out = os.path.join(HERE, "takes", f"{line['id']}_{who}.wav")
        audio, sr = k.create(line["text"].replace("S I S", "S-I-S"), voice=v["kokoro"], speed=v["speed"], lang="en-us")
        audio = resample_poly(audio, 48000, sr).astype(np.float32)
        sf.write(out, audio, 48000)
        print(line["id"], who, f"{len(audio) / 48000:.2f}s")
