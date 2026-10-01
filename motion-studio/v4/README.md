# IntPortal v4: "One Shape"

A 1:30 loop at 130 BPM: 7 phrases × 7 bars = 196 beats = 5428 frames at 60 fps. One shape is never cut. It morphs from the "Sign in" pill through a phone, five forms of Isko, a tablet, a Mac and a PC, the campus grid and the Beta Pass, and back to the pill. The last frame equals the first.

## Layout

- **`src/lib/motion.ts`**: the beat grid (`B`, `bt`) and the motion helpers:
  - closed-form `spring`
  - `track`, which adds one spring per key and never restarts
  - `indicator`, with a stiff lead edge and a soft trail edge
  - `swapAlpha`, which gives content its own enter and exit timing
  - `loopT`, plus `press` for clicks and drags
- **`src/phrases/p*.tsx`**: each phrase's keys for the Shape, camera, cursor, clicks, drags and per-beat events. `src/screens/*` holds the phone UI.
- **`hyperframes/*.html`**: the Isko artform clips (pixel, ASCII, 3D obsidian, halftone). They are seek-driven and rendered to alpha WebM in `public/clips/`.
- **`audio/`**:
  - `cues.json`: from `scripts/cues.ts`.
  - `vo.json`: the voice lines and their beats.
  - `eleven.py`: ElevenLabs music and voice.
  - `temp_score.py` and `temp_vo.py`: stand-ins.
  - `mix.py`: the mix.
  - `beats.py`: measures the beat grid.

## Build

```sh
npm ci
node scripts/clips.mjs                     # HyperFrames clips (uses beats.json)
npx esbuild scripts/cues.ts --bundle --platform=node --format=esm --outfile=out/cues.mjs \
  --loader:.tsx=tsx --jsx=automatic --packages=external && node out/cues.mjs   # cue list + dead-beat check
python3 audio/temp_score.py && python3 audio/temp_vo.py && python3 audio/mix.py temp
scripts/render.sh                          # Remotion -> out/v4-video.mp4
ffmpeg -i out/v4-video.mp4 -i audio/mix.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k out/intportal-v4.mp4
```

## Switching to ElevenLabs

This needs `api.elevenlabs.io` allowed in the environment's network settings and `ELEVENLABS_API_KEY` set as an environment variable. Never put the key in a file.

```sh
python3 audio/eleven.py music              # audio/music_el.mp3
python3 audio/eleven.py voices             # audition 3 voices on line 1
python3 audio/eleven.py vo <voice_id>      # every line
python3 audio/mix.py el                    # fits the track to 90.467 s, mixes
python3 audio/beats.py                     # measured grid -> beats.json
node scripts/clips.mjs && scripts/render.sh   # re-render on the measured grid
python3 audio/mix.py el                    # final mix on the new grid
```

## Checks

- **Determinism:** no `Math.random`, `Date`, timers, CSS transitions, `will-change` or gradients.
- **Loop:** frames 0, 5426 and 5427 render pixel-identical.
- **Dead beats:** `scripts/cues.ts` fails if any beat has no event.
- **Scores:** see `QA.md`.
