"""Temp VO (stand-in until ElevenLabs is reachable): Kokoro af_heart, one
young female voice, every line in vo.json -> audio/vo/temp/<id>.wav (48 kHz)."""
import json, os
import numpy as np, soundfile as sf
from kokoro_onnx import Kokoro
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
K = os.path.join(HERE, "..", "..", "audio", "kokoro")
k = Kokoro(os.path.join(K, "kokoro-v1.0.onnx"), os.path.join(K, "voices-v1.0.bin"))
os.makedirs(os.path.join(HERE, "vo", "temp"), exist_ok=True)
for l in json.load(open(os.path.join(HERE, "vo.json")))["lines"]:
    a, sr = k.create(l["text"], voice="af_heart", speed=l.get("speed", 1.02), lang="en-us")
    a = resample_poly(a, 48000, sr).astype(np.float32)
    sf.write(os.path.join(HERE, "vo", "temp", f"{l['id']}.wav"), a, 48000)
    print(l["id"], f"{len(a) / 48000:.2f}s", f"{len(a) / 48000 / (90.4667 / 196):.1f} beats")
