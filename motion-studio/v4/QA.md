# v4 QA log

Rubric: hook · readability · motion · variety · brand · sync · loop seam. Each is scored 1–10, and the target is 8+ on every one.

Tools:
- `scripts/stills.mjs` + `scripts/sheet.py`: one frame per beat.
- `scripts/cues.ts`: every beat has an event.
- The frame-diff scan in the round log.
- The seam check: Remotion stills of frames 0, 5426 and 5427.

## Round 1 (first full render)

| Criterion | Score | Notes |
|---|---|---|
| Hook | 8 | Sign in → spinner → "Session expired" → Attempt 3 lands in 6 s. The pain is clear before the phone appears. |
| Readability | 7 | Gray mid-morph frames on paper↔ink fills (b7, b10, b116, b184). The campus caption was too small. |
| Motion | 7 | One whip pan at b78 (frame-diff spike 24.6 vs median 0.21). The 3D Isko smeared on exit (b127). |
| Variety | 9 | Line art, pixel sprite, ASCII, 3D obsidian, halftone; themes, device reflow, map, cards, quiz, grid. |
| Brand | 8 | Warm gray / ink / paper, Geist only, 1.75 px icons. Isko is the only colour. |
| Sync | 8 | Every one of the 196 beats has an event, and each spring starts on its beat (0 dead beats). The temp score is on the same grid. |
| Loop seam | 10 | Frames 5426, 5427 and 0 are pixel-identical (PNG). The cursor rests at C0 with zero speed. |

Fixes:
1. Fills run on the snappy spring, so colour resolves ahead of the geometry.
2. Artform clips exit by opacity only, with no blur.
3. The b78 pan is framed wider (z 2.0 → 1.55), with less travel.
4. The campus caption went from 30 to 40 px.

## Round 2 (after fixes)

| Criterion | Score | Notes |
|---|---|---|
| Hook | 8 | Unchanged. |
| Readability | 8 | Cards and the wordmark resolve white within about 0.15 s. The caption is legible at z 1.0. |
| Motion | 8 | No pan spikes besides the deliberate dive into the PUP tile at b167. The 3D Isko exits cleanly. |
| Variety | 9 | Unchanged. |
| Brand | 8 | Unchanged. |
| Sync | 8 | Unchanged. Re-measure once the ElevenLabs track replaces the temp score. |
| Loop seam | 10 | Unchanged. |

Every score is 8+.

## Round 3 (final render)

- **b78:** the camera now pulls back while the pill drops to the bar, then pushes in on the typing. Its largest frame jump fell from 24.6 to 17.1, on par with the deliberate dive into the PUP tile at b167 (16.7).
- **Final file:** 1920×1080, 60 fps, 5428 frames, H.264 CRF 16, yuv420p. Audio is −14.0 LUFS and −1.3 dBTP.
- **Scores:** unchanged from round 2, all 8+. Motion holds at 8.
