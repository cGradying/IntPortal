"""ElevenLabs music + girl VO for v4.

    python3 audio/eleven.py music        -> audio/music_el.mp3 (7 sections x 28 beats, 130 BPM, sax solo in 5)
    python3 audio/eleven.py voices       -> audio/vo/audition/<voice>.mp3 (line 1 in 3 young female voices)
    python3 audio/eleven.py vo <voice_id> -> audio/vo/el/<id>.mp3 for every line in vo.json

The API key is read from the ELEVENLABS_API_KEY environment variable only;
it is never written to disk or into the repo.
"""
import json, os, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://api.elevenlabs.io/v1"
KEY = os.environ.get("ELEVENLABS_API_KEY")
FRAMES, FPS, NB = 5428, 60, 196
SECTION_MS = round(FRAMES / FPS / 7 * 1000)  # 12,924 ms = 7 bars at ~130 BPM


def call(path, body=None, query=""):
    if not KEY:
        sys.exit("Set ELEVENLABS_API_KEY in the environment (not in a file).")
    req = urllib.request.Request(f"{API}{path}{query}", data=json.dumps(body).encode() if body else None,
                                 headers={"xi-api-key": KEY, "Content-Type": "application/json"},
                                 method="POST" if body else "GET")
    with urllib.request.urlopen(req, timeout=600) as r:
        return r.read()


GLOBAL = ["130 BPM", "4/4", "modern neo-soul pop with crisp electronic drums", "warm Rhodes keys", "tight sub bass",
          "clean, airy mix", "every beat has a small rhythmic accent", "instrumental"]
NEG = ["vocals", "singing", "lyrics", "tempo changes", "long silence", "lo-fi crackle"]
SECTIONS = [
    ("Intro", ["soft Rhodes chords", "muted kick on every beat", "finger snaps on 2 and 4", "builds slightly"]),
    ("Groove", ["full drums enter", "syncopated sub bass", "hi-hat sixteenths", "Rhodes stabs"]),
    ("Build", ["add claps", "rising synth arp", "bass walks up", "energy climbing"]),
    ("Peak", ["full band", "big but clean", "open hi-hats", "bright chord stabs on every beat"]),
    ("Sax solo", ["expressive tenor saxophone solo leads", "stripped groove: kick, rim, bass", "sax phrases answer the beat", "jazzy and joyful"]),
    ("Full band", ["full band returns", "sax answers the keys in short call-and-response licks", "driving and warm"]),
    ("Outro", ["groove thins back to Rhodes and muted kick", "resolves to the intro chord so the track can loop", "no fade out, ends on the downbeat"]),
]


def music():
    plan = {
        "positive_global_styles": GLOBAL,
        "negative_global_styles": NEG,
        "sections": [{"section_name": n, "positive_local_styles": s, "negative_local_styles": [], "duration_ms": SECTION_MS, "lines": []}
                     for n, s in SECTIONS],
    }
    audio = call("/music", {"composition_plan": plan, "model_id": "music_v1"}, "?output_format=mp3_44100_192")
    open(os.path.join(HERE, "music_el.mp3"), "wb").write(audio)
    print("music_el.mp3", len(audio), "bytes")


# young, warm, conversational female voices from the default library
AUDITION = {"Jessica": "cgSgspJ2msm6clMCkdW9", "Laura": "FGY2WhTYpPnrIDTdsKH5", "Sarah": "EXAVITQu4vr4xnSDxMaL"}


def tts(voice, text, out):
    body = {"text": text, "model_id": "eleven_multilingual_v2",
            "voice_settings": {"stability": 0.45, "similarity_boost": 0.8, "style": 0.25, "use_speaker_boost": True}}
    open(out, "wb").write(call(f"/text-to-speech/{voice}", body, "?output_format=mp3_44100_192"))


def main():
    lines = json.load(open(os.path.join(HERE, "vo.json")))["lines"]
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "music":
        music()
    elif cmd == "voices":
        os.makedirs(os.path.join(HERE, "vo", "audition"), exist_ok=True)
        for n, v in AUDITION.items():
            tts(v, lines[0]["text"], os.path.join(HERE, "vo", "audition", f"{n}.mp3"))
            print(n)
    elif cmd == "vo":
        os.makedirs(os.path.join(HERE, "vo", "el"), exist_ok=True)
        for l in lines:
            tts(sys.argv[2], l["text"], os.path.join(HERE, "vo", "el", f"{l['id']}.mp3"))
            print(l["id"])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
