# 054 The reel

**Status:** shipped (46 s; 8.3 MB at 9:16, 7.3 MB at 16:9; −14.1 LUFS, −1.5 dBFS peak)

## What changes for the student

On the website's `/reel`, and wherever it is shared, a short film shows what IntPortal is and why a PUP student would want it, in under a minute. It ends on where to get it.

## Direction and references

- The October film (`intportal-films/films/beta-60`) set the rules: the film is a pure function of time (`seek(t)`), springs with mass, a new event every 2 to 4 seconds, real screens and no flat mock-ups, cut to the beat, no centred title on a gradient, no generic particles. Those rules carry over.
- What changed since: the Isko mascot is retired (LAR is the only character), the look is the night world of spec 045, the intro is the talk with LAR (049), and there is no waitlist; it is out.
- The screens are the app itself in demo mode, recorded from the browser demo (052) or the iOS simulator, never made-up data that looks real.

## Keep

- Demo data only. No real student number, name, grade or schedule.
- LAR's art and the campus scene come from the app's source.

## Behaviour

- **C1.** `reel/` holds the film's source: `index.html` with `seek(t)`, the shot list, the score and the render script. `node reel/render.mjs` renders it with the bundled Chromium and ffmpeg.
- **C2.** Two cuts from one timeline: 9:16 at 1080 × 1920 and 16:9 at 1920 × 1080, 60 fps, 40 to 50 seconds.
- **C3.** The story, in acts:
  1. The pain: PUP SIS at a bad moment (a slow page, a session expired), in a few seconds.
  2. The portal builds from its pentomino tiles and LAR comes through.
  3. The day: Today's countdown, a deadline ticked Done, the week, grades and the trend, a card flipped.
  4. The promise: works offline, stays on your phone, unofficial and free.
  5. The end card: IntPortal, the site's address, Android, iPhone, desktop and browser.
- **C4.** Captions are burned in for the shared files and also published as a WebVTT file for the site's player.
- **C5.** The score is made in code (the free voice and music plan has no music); the mix is at −14 LUFS and at most −1 dBTP. No voice-over, so it works muted.
- **C6.** Before the full render, a contact sheet is scored on the October film's rubric, and the three worst shots are fixed until every score is 8 or more. The scores are kept in `reel/REVIEW.md`.
- **C7.** `/reel` plays the 16:9 cut on wide screens and the 9:16 cut on phones, with a poster frame, captions, no autoplay with sound, and links to download each file.
- **C8.** Each published file is at most 25 MB.

## Copy

Written with the shot list, in the app's voice. The end card: "IntPortal. Para sa Iskolar ng Bayan." and the site's address.

## Data shape

None outside `reel/`.

## Errors

None for the student.

## Motion and Reduce Motion

The page never autoplays; with Reduce Motion it shows the poster and a play button only.

## Accessibility

Captions (C4). The player's controls are the browser's own.

## Out of scope

- A voice-over. It can be added later with the free voice plan; the film works without one.

## Test map

| Criterion | Check |
|---|---|
| C1, C2, C8 | the render script's output and `ffprobe` |
| C5 | `ffmpeg -af loudnorm` measurement in the render log |
| C6 | `reel/REVIEW.md` |
| C7 | screenshots of `/reel` at 375 and 1440 px |

## Open questions

None.
