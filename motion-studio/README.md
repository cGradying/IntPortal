# IntPortal launch film — "Step Through"

A 95 s, 1920×1080, 60 fps launch film, built as code. Every frame is a pure function
of time: `window.seek(t)` paints frame t, with no clocks, no retained state and seeded
noise only. `node qa/lint.mjs` enforces this.

## Make it

```sh
sudo apt-get install -y ffmpeg          # brew install ffmpeg on macOS
pip install numpy scipy librosa soundfile pyloudnorm pillow kokoro-onnx
npm i                                   # playwright, three, fonts

python3 audio/score.py                  # synth score → audio/music.wav (124 BPM, 48 bars)
python3 audio/beats.py                  # measured beat grid → beats.json
# VO weights (Kokoro-82M, local): into audio/kokoro/
#   https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
#   https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
python3 audio/vo/gen_kokoro.py          # script.json → audio/vo/takes/*.wav
python3 audio/mix.py                    # SFX + VO + ducked music → audio/mix.wav (−14 LUFS, −1 dBTP)

node qa/lint.mjs                        # render contract: banned APIs + seek determinism
node qa/contact.mjs --tag r1            # one frame per beat → out/qa/r1-*.png
node render.mjs                         # → out/intportal-launch.mp4 (H.264, yuv420p, CRF 16)
```

`node render.mjs --fps 30 --scale 0.5 --out out/preview.mp4` renders a fast preview.
`node qa/frames.mjs 23.5 41` writes full-res stills at given beats.

## Layout

- `timeline.json`: BPM, bars and the section map shared by the score and the film.
- `film/src/scenes/`: hook, world (void, portal, Isko, warp), ios, rooms, platforms,
  sync (PUPSIS), hub (campus network), outro (beta waitlist), flash.
- `film/src/art/`: portal swirl shader (a port of the app's `Portal.metal`), Isko 2.0
  rig, the new 3D campus, and the dotted Philippines map.
- `film/src/ui/`: the app rebuilt for the camera: phone screens, all 15 rooms (ported
  from `intportal-app/src/lib/rooms.ts`), and the macOS, Windows and web surfaces.
- `audio/`: score, beat measurement, VO script and generation, SFX and mix.
- `qa/`: contact sheets, lint, frame tools, and `scores.md` (the QA loop log).

## Before publishing

- Set `WAITLIST_URL` in `film/src/scenes/outro.js` (it currently reads "link in the post").
- Other universities appear by name only, labelled "Not connected yet". There are no
  seals or marks. Campus counts come from public sources (Wikipedia, university sites).
