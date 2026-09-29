# IntPortal launch film — "Step Through" (v2)

A 1:56, 1920×1080, 60 fps launch film, built as code. Every frame is a pure function
of time: `window.seek(t)` paints frame t, with no clocks, no retained state and seeded
noise only. `node qa/lint.mjs` enforces this.

## Make it

```sh
sudo apt-get install -y ffmpeg          # brew install ffmpeg on macOS
pip install numpy scipy librosa soundfile pyloudnorm pillow kokoro-onnx
npm i                                   # playwright, three, fonts

python3 audio/score.py                  # synth score → audio/music.wav (128 BPM, 61 bars, drop + bomb)
python3 audio/beats.py                  # measured beat grid → beats.json
# VO weights (Kokoro-82M, local): into audio/kokoro/
#   https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
#   https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
python3 audio/vo/gen_kokoro.py          # script.json → audio/vo/takes/*.wav
python3 audio/mix.py                    # SFX + VO + ducked music → audio/mix.wav (−14 LUFS, −1 dBTP)

node qa/lint.mjs                        # render contract: banned APIs + seek determinism
node qa/contact.mjs --from 0 --to 244 --tag v2r1   # one frame per beat → out/qa/v2r1-*.png
node render.mjs --out out/intportal-launch-v2.mp4  # H.264, yuv420p, CRF 16
```

`node render.mjs --fps 30 --scale 0.5 --out out/preview.mp4` renders a fast preview.
`node qa/frames.mjs 23.5 41` writes full-res stills at given beats. `node qa/sheet-isko.mjs`
renders Isko's model sheet.

The mix sets loudness with a static gain and an oversampled limiter rather than
`loudnorm`, which would switch to dynamic mode and flatten the mid-film drop.

## The cut (beats at 128 BPM)

| Beats | Scene | File |
|---|---|---|
| 0–16 | Cold open: glitch type, the old sign-in loop, SESSION EXPIRED, the crack | `scenes/open.js` |
| 16–36 | Shards magnet-snap into the portal; Isko is born; Step Through switch; warp | `scenes/magnet.js` |
| 36–100 | iOS in four chapters: Today, Schedule, Grades, Notes → cards | `scenes/ios.js` |
| 100–116 | The film inside a pixel motion editor; room switches flip on the beat | `scenes/editrooms.js` |
| 116–132 | iOS · Mac · PC, cards snapping device to device | `scenes/platforms.js` |
| 132–148 | PUP SIS in three steps, Mabini "soon"; tape stop | `scenes/sync.js` |
| 148–164 | The drop: Wi-Fi drains, Airplane mode clicks alone | `scenes/drop.js` |
| 164–200 | The bomb: on-device RAG, then summaries, plans, cards, quizzes, targets | `scenes/ai.js` |
| 200–224 | Hub of major universities → 100+ universities and colleges on the map | `scenes/hub.js` |
| 224–end | Beta Pass IDs with a pixel face per person → waitlist → end card | `scenes/faceid.js` |

## Layout

- `timeline.json`: BPM, bars and the section map shared by the score and the film.
- `film/src/art/`:
  - The portal swirl shader, a port of the app's `Portal.metal`.
  - `isko.js`: Isko 3.0, the portal-spirit helper, a layered hi-bit rig.
  - `faces.js`: the ten pixel students.
  - The 3D campus and the dotted Philippines map.
- `film/src/ui/`:
  - The app rebuilt for the camera: phone screens and all 15 rooms (ported from `intportal-app/src/lib/rooms.ts`).
  - The Mac and Windows surfaces.
  - `pixtype.js`: glitch type (sans ↔ pixel face, chromatic split).
  - `switch.js`: pixel toggles.
  - `thread.js`: light-threads.
  - `oldportal.js`: the generic old sign-in page.
- `film/src/data/schools.js`: names and city-level coordinates for the network teaser.
- `audio/`: score, beat measurement, VO script and generation, SFX and mix.
- `qa/`: contact sheets, lint, frame tools, and `scores.md` (the QA loop log).

## Before publishing

- Set `WAITLIST_URL` in `film/src/scenes/faceid.js` (it currently reads "link in the post").
- Other universities and colleges appear by name only, labelled "not connected yet". There
  are no seals or marks, and map positions are city-level approximations for a vision teaser.
