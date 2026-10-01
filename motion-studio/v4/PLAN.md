# IntPortal v4: "One Shape", a 1:30 Dribbble-grade loop (130 BPM, 7 × 7 bars)

## The brief (user's words, kept as the source of truth)
- **Scope:** "improve the whole animation itself, redo it from the base". The old assets can still be used.
- **Motion:** "smoothen out the animations between functions". Go back to doing QA after.
- **Music:** new, 130 BPM, 7 bars, with a saxophone solo. "Something happens every beat (dynamically)."
- **Voice:** the girl only, via ElevenLabs.
- **Direction:**
  - Dribbble-level UI motion.
  - One shape, never cut: every state is the same element morphing its size, radius and color while its content swaps with a short blur.
  - A cursor drives every change with real clicks and drags.
  - Light warm-gray canvas, black and white components, one clean UI font (Geist).
  - Springs everywhere, with a tiny overshoot at most.
  - The camera zooms so each state fills the frame.
  - The last frame is the first frame, so it loops.
- **Banned:** bouncy easing, particle bursts, glows, gradients on UI chrome, mismatched icon strokes, dead time, anything that looks like a template.
- **Content:**
  - Use more types of artform, with animations integrated where needed.
  - A new mobile UI that shows what the app could become, not today's screens.
  - Appealing, with not too many assets, and interacted with on screen.
- **Springs (from the user's resource):**
  - Closed-form `spring(t, k, d)`.
  - `track(t, keys)` adds one spring per target change and never restarts.
  - `indicator()` gives a tab indicator a stiffer lead edge than its trail edge.
  - `swapAlpha()` gives text inside a morphing box its own in and out timing.
  - `loopT()` wraps time for the loop.
- **Tools:** HyperFrames and Remotion.
- **References:** x.com/0xMovez/…2104216919033192746, x.com/achxvi/…2103918792845963545 and x.com/himanshutwtxs/…2103495232637882858. All three are blocked by the network here.
- **Gotchas:**
  - No `will-change` on anything the camera scales.
  - Swapped text gets its own enter and exit timing.
  - The last frame equals the first, including cursor position and speed.
- **Answers to my questions:**
  - Length: 7 × 7 bars (≈1:30).
  - Music: ElevenLabs Music.
  - Engine: both Remotion and HyperFrames.
  - Isko: appears "as many kinds of form".

## Context
v3 (1:56, pixel-portal style) is delivered. The user now wants a new film built from the base in a different language: monochrome product-motion, one continuous morphing shape, cursor-driven, looping. The story stays IntPortal's:
- the sign-in pain
- the future app
- the on-device AI
- PUP SIS
- 100+ campuses
- the beta waitlist

The old code stays in `motion-studio/` (v3). v4 is a new project beside it that reuses data and art: `faces.js`, `schools.js`, Isko sprite code, and the portal shader for the 3D Isko.

**Blockers the user must clear before audio:**
- **Allow `api.elevenlabs.io`:** in the cloud environment menu, choose Edit, then Network access, and add the allowed domain.
- **Set the key:** add `ELEVENLABS_API_KEY` as an environment variable. The key pasted in chat should be rotated, and it is never written into code or commits.
- **Skill install:** GitHub currently returns 403, so `npx skills add heygen-com/hyperframes` fails. I use the npm packages instead (`hyperframes@0.8.105`, Remotion 4.0.532, `geist@1.7.2`), and retry the skill install if GitHub opens.

**Visual work does not wait on the blockers.** It is built against a provisional beat grid (130 BPM nominal) and snapped to the measured grid once the music exists.

## Design system
- **Colors:**
  - Canvas: warm gray `#E8E5E0`.
  - Ink: `#0B0B0C`.
  - Paper: `#FFFFFF`.
  - Hairlines: `#0B0B0C14`.
  - The only non-mono color is Isko's pixel form.
- **Type:** Geist Sans only: 600 for display, 500 for UI, plus tabular numerals. Geist Mono appears only inside the ASCII-Isko artform.
- **The Shape:**
  - One React component with animatable props: x, y, w, h, radius, fill, stroke and content.
  - Content swaps use `swapAlpha` plus a 6px blur in and out (≈0.12 s).
  - Every prop is driven by `track(t, keys)` with critically damped springs (k 170 / d 26; ζ≈1, tiny overshoot).
  - There are no CSS transitions.
- **Cursor:**
  - A vector arrow, black with a white 1.5px stroke.
  - Its position comes from `track()` keys; press is a 0.92 scale over 0.1 s.
  - Drags carry the Shape's edge or handle with them.
- **Camera:** a `track()`-driven zoom/pan so each state fills ≈70% of the frame. No `will-change`.
- **Icons:** one set, drawn as SVG, 1.75px stroke, round caps, 24px grid.
- **Every beat:** every beat in the 196-beat grid has a listed event below (a click, a drag step, a number tick, a swap, a camera step or an Isko change).
- **Loop:**
  - Frame 0 and frame N are identical: the "Sign in" pill centered, and the cursor at rest at C0 = (1180, 640) with zero velocity.
  - All keys are set so the last spring settles before the end.
  - The music tail crossfades into its head.

## Engines
- **Remotion is the master timeline** (`motion-studio/v4/`, a TypeScript Remotion project). It covers the Shape, the cursor, the camera, every UI state, and the final render (H.264 CRF 16, yuv420p, 1920×1080, 60 fps).
- **HyperFrames renders the artform interludes as alpha clips** (`motion-studio/v4/hyperframes/`):
  - 3D obsidian Isko, built with three.js from the old `art/portal.js` materials.
  - Pixel Isko.
  - ASCII Isko.
  - Halftone/dither Isko.
  - The 3D campus stack zoom.

  Remotion places each clip with `<OffthreadVideo>` (WebM VP9 alpha, or a PNG sequence if alpha export isn't supported) at its beat, aligned so the Shape hands off with no cut.
- **Determinism:**
  - Remotion is frame-pure (`useCurrentFrame`).
  - HyperFrames clips are seek-driven.
  - The lint carries over: no `Math.random`, `Date`, timers or CSS transitions.

## Audio
- **Music: ElevenLabs Music** (`/v1/music` with a composition plan of 7 sections × 12,923 ms = 90.46 s, all at 130 BPM):
  1. Intro: keys plus a soft kick that builds.
  2. Groove: full drums and bass.
  3. Build.
  4. Peak.
  5. **Sax solo** over a stripped groove.
  6. Full band, with the sax answering.
  7. Outro that resolves back into the intro for the loop.
- **Beat grid:** measure the beats (`audio/beats.py` adapted). If the tempo drifts, time-stretch to 130.00 with ffmpeg; otherwise cut the film to the measured grid.
- **VO:** ElevenLabs TTS, one young, warm, conversational female voice. I audition 3 library voices on line 1 and pick the most natural. Lines are placed on beats:
  - b6: "Nine minutes to class… and you're signed out. Again."
  - b26: "This is IntPortal."
  - b34: "Your whole day, in one place."
  - b62: "Grades land, and it tells you what you need."
  - b86: "Your notes become cards. Ask Isko anything, even offline."
  - b130: "Make it yours."
  - b146: "Works with PUP SIS."
  - b162: "Someday, every campus."
  - b178: "Beta opens soon. Save your spot."
  - b188: "Step through."
- **SFX:** synthesized UI clicks, drag ticks, toggles and soft whooshes on every cursor event (no impacts or risers that fight the track).
- **Mix:** music ducked under VO, static gain to −14 LUFS, and an oversampled limiter for ≤ −1 dBTP (the `mix.py` approach).

## State list on the beat grid
130 BPM: 1 beat = 0.4615 s, 1 bar = 1.846 s, 7 bars = 12.92 s. "b" is the beat index (0–195), and each bar lists its 4 beats.

### Phrase 1 · Hook (bars 1–7, b0–27) · music: intro
| Bar | Shape state | Beat 1 · 2 · 3 · 4 |
|---|---|---|
| 1 | Black pill "Sign in", centered | Cursor leaves C0 · arrives on the pill · hover (pill grows 3%) · click (press) |
| 2 | Pill → circle spinner | The circle forms · spinner step · step · circle → wide card "Session expired" (blur swap) |
| 3 | Card | Cursor clicks "Try again" · card → spinner · back to the card with "×2" · "×3" (number ticks) |
| 4 | Card corner dragged | The cursor grabs the bottom-right corner · drag: the card grows taller · the radius morphs to 56 · it becomes a phone screen (white) |
| 5 | Phone splash | "Int" swaps in · "Portal" · a 1.75px divider line draws · "your campus, in one place" |
| 6 | Phone, camera zooms in | Zoom step · an Island chip grows out of the top edge · chip text "COMP 20073 · 9 min" · Isko form 1 (tiny pixel) peeks from the chip |
| 7 | Today builds | Card 1 settles · card 2 · card 3 · card 4 (each one grows out of the previous card's edge, never a cut) |

### Phrase 2 · Today and Schedule (bars 8–14, b28–55) · music: groove
| Bar | Shape state | Beats |
|---|---|---|
| 8 | The next-class card expands into a hero | Expands · "7:30" rolls in · "in 9 min" · the free-time bar fills |
| 9 | Timeline, dragged up by the cursor | Grab · row 1 snaps · row 2 · release (momentum spring) |
| 10 | The free block opens into a sheet | Click · the sheet grows from the block · "1h 30m free" · suggestion "Library · 3 min" |
| 11 | Sheet dragged down | Grab · drag · the sheet shrinks back into the block · Island chip → "Next · GEED 10053" |
| 12 | Week strip, dragged sideways | Mon → Tue · Wed · Thu · settles on Mon (one indicator stretch per beat) |
| 13 | A class block expands into a detail view | Click · it grows to fill the frame · "Room S512 · 5F" · closes back into the block |
| 14 | Isko form 2: a monochrome line-art chip | The chip forms · "Leave at 7:21." · the chip folds away · the tab indicator stretches (lead/trail) to Grades |

### Phrase 3 · Grades and Notes (bars 15–21, b56–83) · music: build
| Bar | Shape state | Beats |
|---|---|---|
| 15 | GPA card | 3.00 → 2.10 · → 1.60 · → 1.28 (rolling digits) · the sparkline draws |
| 16 | Grade rows | Row 1 lands (1.25) · row 2 (1.50) · row 3 (1.00) · row 4 (1.25) |
| 17 | Goal slider, dragged | Grab at 1.75 · 1.67 · 1.58 · 1.50 (the "needed" value ticks at each step) |
| 18 | The slider morphs into the Coach card | Morph · "Aim for 1.69" · "on the 2 subjects left" · tab indicator → Notes |
| 19 | Note editor | The note grows · cursor drag-selects line 1 · line 2 · line 3 (the selection grows each beat) |
| 20 | The selection pill becomes "Ask Isko" | The pill appears · click · the pill → command bar · the caret blinks |
| 21 | Command bar typing | "What's a" · "balanced" · "BST?" · Enter (press) |

### Phrase 4 · On-device AI (bars 22–28, b84–111) · music: peak
| Bar | Shape state | Beats |
|---|---|---|
| 22 | The note divides into 4 chunk rows (one container, hairline dividers) | Divider 1 · 2 · 3 · each chunk gets a dot |
| 23 | Meaning map: the dots drift into a 2D scatter | Scatter · the question dot lands · 3 nearest dots ring · lines connect |
| 24 | The command bar morphs into the answer card | Morph · the answer streams · citation chip 1 · chips 2 and 3 |
| 25 | Cursor clicks the Wi-Fi toggle | Click · the toggle slides off · an "Offline" chip appears · the answer stays put: "on this phone" |
| 26 | "Make cards" | Click · the note becomes a card stack · stack fans · the top card flips |
| 27 | "Quiz" | Click · 3 options appear · picks B (wrong) · it morphs into a "Why?" explanation |
| 28 | "Plan" | Click · week-plan rows 1–2 · row 3 · the whole Shape shrinks to a black dot (the Isko seed) |

### Phrase 5 · Sax solo: Isko in many forms, rooms, every screen (bars 29–35, b112–139) · music: sax solo
| Bar | Shape state | Beats |
|---|---|---|
| 29 | Isko form 3: the Shape itself as a pebble with two eyes | The dot grows · the eyes open · blink · the mitts appear |
| 30 | Isko form 4: color pixel sprite (HyperFrames clip) | Happy · wow · wink · focus (an expression per beat) |
| 31 | Isko form 5: ASCII Isko in Geist Mono (HyperFrames) | The glyphs cycle per beat · · · and resolve |
| 32 | Isko form 6: 3D obsidian Isko (three.js, HyperFrames) | Turns 90° · 180° · 270° · back to front |
| 33 | Themes: cursor clicks theme dots and the phone re-themes | Light · Dark · Paper · Ink (Isko keeps his color accent) |
| 34 | Cursor drags the phone corner and the layout reflows | Phone → tablet · → Mac window · → PC monitor · hold ("Same you, everywhere" draws on the window title) |
| 35 | Drag back to the phone; Isko form 7: halftone dither | Shrink · phone · the halftone Isko sits on the screen edge · the solo ends |

### Phrase 6 · PUP SIS and campuses (bars 36–42, b140–167) · music: full plus sax answers
| Bar | Shape state | Beats |
|---|---|---|
| 36 | "Connect PUP SIS" button | Click · progress fills 33% · 66% · "Signed in ✓" (width spring) |
| 37 | SIS rows slide in as cards | Schedule · Grades · Room · "Synced just now" |
| 38 | A "Mabini · soon" chip grows from the button's side | Grows · flips · folds away · the camera starts zooming out |
| 39 | The phone becomes 1 tile in a stack of school tiles (3D, HyperFrames) | The stack appears · 8 · 16 · 32 (stack-height counter) |
| 40 | The stack deals into page 1 (8×4 grid) | Row 1 · 2 · 3 · 4 |
| 41 | Pages turn | Page 2 · counter 64 · page 3 · 96 |
| 42 | "100+ universities and colleges" | Page 4 · "100+" rolls · "not connected yet" · the camera zooms back into the PUP tile |

### Phrase 7 · Beta waitlist and loop (bars 43–49, b168–195) · music: outro back into the intro
| Bar | Shape state | Beats |
|---|---|---|
| 43 | The tile morphs into the Beta Pass ID | Morph · pixel face 1 · face 2 · face 3 |
| 44 | ID faces and name | Faces 4 · 5 · 6 · "EARLY ACCESS" stamp (spring, no bounce) |
| 45 | Email field | Click · "you@" · "school" · ".edu.ph" (typed per beat) |
| 46 | "Join the waitlist" | Click · button → spinner · "You're in ✓" · the pass shrinks |
| 47 | Wordmark | "IntPortal" · "Step through." · the divider draws · the Isko pixel form winks |
| 48 | The wordmark morphs back into the black pill | Pill · "Sign in" swaps in · the cursor starts back toward C0 · glide |
| 49 | The loop lands | Cursor settling · settling · at rest at C0 · frame 195 + 1 ≡ frame 0 |

## Build steps
1. **Scaffold `motion-studio/v4/`:**
   - Remotion (`npx create-video` equivalent via npm), `geist` and `hyperframes`.
   - `lib/motion.ts`: closed-form `spring`, `track`, `indicator`, `swapAlpha`, `loopT`, `beat(b)` and `bt(t)` against `beats.json`.
2. **Core components:** `<Shape>`, `<Cursor>`, `<Camera>`, an icon set, and the new future-app screens (Today, Schedule, Grades, Notes, AI answer, Offline, Cards/Quiz/Plan, Themes, Responsive, Sync, Pass). All are black and white, in Geist.
3. **Timeline:** `timeline.ts` holds the beat-indexed key table above as data. Every component reads its keys from it, so the state list *is* the code.
4. **HyperFrames clips:** pixel, ASCII, 3D obsidian and halftone Isko, plus the 3D campus stack, rendered with alpha at 1080p60 and placed in Remotion at their beats.
5. **Audio:** once ElevenLabs is reachable, generate music (composition plan), measure beats, audition and generate VO, place SFX on the cursor events, then mix.
6. **QA loop** (as before):
   - A contact sheet with one frame per beat (196) and a 30 fps preview.
   - Score hook, readability, motion, variety, brand and sync, plus a new **loop seam** check (frame N vs frame 0 pixel diff, and cursor velocity at both ends).
   - Fix the 3 worst problems each round until all are 8+.
7. **Final render** (Remotion, H.264 CRF 16), then a share encode under 30 MiB and the master in parts. Commit and push to `claude/intportal-launch-video-pndlsa` (no key in the repo).

## Verification
- Lint: no banned APIs and no `will-change`. Determinism: seek the same frame twice and get matching pixels.
- Loop: the first and last frames differ by ≤ rasterizer noise, and cursor speed is 0 at both ends.
- Every beat b0–195 has at least one event in `timeline.ts`; a script asserts no beat is dead.
- `ffprobe`: 1920×1080, 60 fps, ≈90.5 s. `ebur128`: −14 ±0.5 LUFS, ≤ −1 dBTP.
- Visual peaks sit within 1 frame of the measured beats.
- The contact-sheet rubric scores 8+ on every criterion, logged in `qa/scores.md`.
