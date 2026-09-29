# QA loop log

Method: `node qa/contact.mjs --from 0 --to 192 --step 1 --tag rN` renders one frame per
beat (a beat + 0.12 s, so hits have landed) into 8x6 sheets at 400 px per cell, about
the size the film is seen at on a phone. Motion and sound sync are judged on a
low-res preview (`node render.mjs --fps 30 --scale 0.5 --out out/preview.mp4`).

Scores are 1–10. The loop stops when every score is 8 or higher.

## Round 1

| Hook (first 2 s) | Phone readability | Motion | Variety | Brand | Sound sync |
|---|---|---|---|---|---|
| 6 | 7 | 7 | 8 | 8 | 8 |

Three worst problems, and what changed:
1. **Weak hook.** Beat 0 was near-black with a tiny pixel, and "Class" landed late.
   Now the words land on beats 0, ½, 1 and 1½ at 400–600 px over a moving gold
   dot-grid floor, with a maroon 7:21 → 7:22 clock, and the SFX moved with them.
2. **Near-empty transition frames** (beats 67, 108, 172–173). The iOS exit spin is
   shorter (67.1 → 68.2). The sync plate and phone start their springs before the
   cut. The outro opens on the swirl at 3.6x collapsing into the icon.
3. **Small UI in sync.** The phone is 1.08x at first, then pushes to 1.85x on the
   IntAssis chat, so the question and answer read at phone size.

## Round 2

| Hook (first 2 s) | Phone readability | Motion | Variety | Brand | Sound sync |
|---|---|---|---|---|---|
| 8 | 8 | 8 | 8 | 8 | 8 |

Checks:
- Hook: full-frame kinetic type from frame 0, and the VO starts at 0.24 s.
- Readability: every VO line has a headline of 96 px or larger. The UI close-ups
  (Today, Grades stamps, flashcards, IntAssis) read at 1/3 scale. The wide platform
  shot is the only small-UI frame, and it is labelled per device.
- Motion: springs on every camera move, and no fades as the default entrance. The
  preview shows no pops or jumps between scenes.
- Variety: something new at least every 2–4 s in every section (checked across the
  193-frame sheet).
- Brand: Montserrat/Source Sans 3 with Pixelify only inside product UI, the app's
  gold `#F5B227` and maroon `#7A1128`, the real 15 rooms, Isko's outfit, and the
  portal icon.
- Sound: every cue sits on `beats.json` (measured median drift 0 ms). Loudness is
  −14.0 LUFS, and true peak is −1.2 dBTP.

Round 2 still had three motion problems, visible in a 16-frame strip around each cut
of the preview (`out/qa/strips.png`):
1. **Warp flash held white ~0.2 s**, then the phone arrived tiny through a gray wash.
   Now the flash rises over 0.4 beat and clears by 20.55, and the phone lands from
   −1400 px on a stiffer spring.
2. **The phone spin showed the screen mirrored from behind.** The phone now has a
   real back (titanium-maroon, camera plate, wordmark) with backface culling.
3. **Slow `screen`-blend flash rises looked muddy gray** into the hub and outro. The
   flashes are now opaque and fast (0.3 beat rise).

Objective sync check on the preview: 65 visual-change peaks sit a median 29 ms from
the nearest measured beat (under 1 frame at 30 fps), and 78.5% are within 2 frames
of an audio onset.

## Round 3 (final)

| Hook (first 2 s) | Phone readability | Motion | Variety | Brand | Sound sync |
|---|---|---|---|---|---|
| 8 | 8 | 8 | 9 | 9 | 8 |

Every score is 8 or higher → full render.

## Final render check

`out/intportal-launch.mp4`: H.264, yuv420p, 1920×1080, 60 fps, 95.1 s, −14.0 LUFS,
−1.4 dBTP. A strip of every 4th frame through the cuts found one more flicker: the
iOS scene cut in 0.3 beat before the warp flash peaked (cream → dark → cream). The
cut now sits under the flash peak (beat 19.93). Seconds 9–11 were re-rendered
(`node render.mjs --from 9 --to 11`) and spliced into the master, which has 5,706
frames with no visible seam.

---

# v2 ("Pixel Magnet" revision)

Same method, 244 beats at 128 BPM: `node qa/contact.mjs --from 0 --to 244 --step 1 --tag v2rN`.

## v2 Round 1

| Hook (first 2 s) | Phone readability | Motion | Variety | Brand | Sound sync |
|---|---|---|---|---|---|
| 8 | 7 | 7 | 8 | 8 | 8 |

Three worst problems, and what changed:
1. **"Made for you" read as confetti.** The cards were small and only visible for part of each beat. Now each card builds in 0.35 beat from fewer, closer fragments, holds big (2.2x) while its word is spoken, and settles into a 3 + 2 grid at 1.18x.
2. **Empty frames at beats 184–185.** The RAG answer, the meaning map and the on-device chip now hold until 185.5, so the frame never goes empty before "Summaries".
3. **Cold-open retry text sat behind the page.** "Sign in again." / "Wrong captcha." are smaller and clear the page. The "iPhone" label sits below the device, and the wide three-device shot is 20% bigger.

Also: the iOS chapters now alternate sides (phone right for 01/03, left for 02/04), so the 64-beat section does not hold one composition.

## v2 Round 2

| Hook (first 2 s) | Phone readability | Motion | Variety | Brand | Sound sync |
|---|---|---|---|---|---|
| 8 | 8 | 8 | 8 | 8 | 8 |

Checked on a 30 fps half-scale preview (`out/preview-v2.mp4`) with 10-frame strips around every cut (`out/qa/strips-v2.png`):
1. **Warp into iOS held white for about 0.4 s.** The swirl now stays as chunky dithered pixels through the dive, and the flash is 0.55 beat, so only 2 frames are white.
2. **iOS composition was the same for 64 beats.** Chapters alternate sides: phone right for 01/03 and left for 02/04, with the labels, Isko (mirrored) and his light-thread following.
3. **Mirrored labels ran off the right edge, and Isko sat on the description.** Labels moved to x 1060 with a smaller long title, and Isko sits lower.

Sync: 47 visual-change peaks on the preview. Measured against the eighth-note grid, the off-beat peaks are the intended half-beat events: clicks at 8.5 and 11.5, the 16 hub ignitions on half beats, and the made-for-you builds at 187.5 and 190.5. The SFX sit on the same half beats. The drop (beats 150–160) is 13.8 dB RMS below the bomb bar (164–168).

Every score is 8 or higher → full render.
