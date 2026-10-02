# IntPortal launch film: combined prompt

This is one paste-ready prompt covering the two most recent films:
- **v3 "Step Through":** dark pixel-portal world, 1:56 at 128 BPM.
- **v4 "One Shape":** light monochrome product motion, a 1:30 loop at 130 BPM.

Paste everything below the line. Set `CUT` to one of:
- `A` for v3 only
- `B` for v4 only
- `A+B` for one combined film in which v3 steps through the portal into v4

---

You are a motion studio. Make a launch video for **IntPortal**, a student app for PUP (Polytechnic University of the Philippines) that replaces the painful PUP SIS sign-in with a calm, offline-first campus companion. Its helper AI is **Isko**.

**CUT = A+B**

## 0. Shared foundation (applies to every cut)

### Story beats, in order
1. The pain: "Nine minutes to class… and you're signed out. Again."
2. IntPortal opens. The portal or the shape becomes the app.
3. Your day: schedule, free time, rooms.
4. Grades land, and the app tells you what you need.
5. Notes become study material. Isko answers from your own notes, on the device and offline (RAG: chunks, then a meaning map, then nearest passages, then a cited answer, then cards, a quiz and a plan).
6. Make it yours: themes, then phone, Mac and PC (iOS, Mac and PC only).
7. Works with PUP SIS. Someday, every campus: 100+ universities and colleges, public and private, not connected yet.
8. The Beta waitlist: a Beta Pass ID with per-person pixel faces. "Step through."

### Isko
- A cute, non-human portal spirit (Ember Knights energy):
  - an obsidian pebble body
  - stepped block ears
  - a dark visor with big gold eyes
  - a belly window showing the portal swirl
  - a gold spark antenna
  - floating mitts and an orbiting gold cube
- He appears in many forms:
  - fireball, then obsidian ball, then hi-bit pixel sprite
  - the UI shape itself with two eyes
  - monochrome line art
  - ASCII (glyphs cycle per beat, then resolve to colour)
  - faceted 3D obsidian turning a quarter per beat
  - halftone dots
- Isko's gold and purple are the only colour allowed in the monochrome film.
- He comments on what the user is doing ("Leave at 12:50.", "Aim for 1.19").

### Pixel faces
- 10 students, 20×24 pixel portraits built from traits (skin, hair, glasses, hijab, cap, shirt): Migs, Aya, Jun, Noor, Paolo, Tala, Bea, Rafa, Kim, Lia.
- They fill the Beta Pass one face per beat, then an "EARLY ACCESS" stamp lands.

### Schools
- 16 majors (UP, PNU, TUP, UST, DLSU, Ateneo, FEU, Mapúa, BatStateU, CvSU, BulSU, SLU, WVSU, USC, CTU, MSU), plus 135 more public and private schools.
- PUP SIS is the only live one.
- Names only: no seals and no marks.

### Voice
- One young, warm, conversational girl's voice (ElevenLabs). Short lines placed on beats.
- **Music:** ElevenLabs Music, generated from a section-by-section composition plan.
- **Mix:** VO ducks the music. −14 LUFS integrated, ≤ −1 dBTP true peak.

### Craft rules
- **Determinism:**
  - Every frame is a pure function of time (`seek(t)`), using seeded noise only: no `Math.random`, clocks or CSS transitions.
  - Every visual change lands on the measured beat grid, and something happens on every beat.
- **Springs:**
  - Closed-form springs (k 170, d 26, ζ≈1), a tiny overshoot at most.
  - `track(t, keys)` adds one spring per target change and never restarts.
  - `indicator()`: the lead edge is stiff and the trail edge soft.
  - `swapAlpha()`: swapped text gets its own enter and exit timing, with a short blur.
- **Banned:**
  - bouncy easing, particle bursts, glows on UI chrome
  - gradients on UI chrome, fade-ins from nothing, a centered title on a gradient, corner labels
  - mismatched icon strokes, dead time, anything that looks like a template
- **Delivery:**
  - 1920×1080 at 60 fps, H.264 yuv420p CRF 16.
  - A QA contact sheet (one frame per beat), scored on hook, readability, motion, variety, brand, sync and loop seam. Loop the fixes until every score is 8+.

## A. v3 "Step Through" (dark pixel-portal world, 128 BPM, 61 bars ≈ 1:56)

### Look
- A night-violet world with three.js depth (bloom only on the portal light, never on UI).
- Procedural pixel art. PUP maroon and gold swirl inside an obsidian portal.

### Type
- SDF morph type that morphs (never glitches) between a clean sans and a pixel font, in different sizes.
- Glyph bands scatter side by side.
- Thin geometry (rules, squares, rings, crosshairs, corner brackets) draws around the words.
- Chromatic spectral edges, not rainbow colour.

### Sections (in beats)
1. **Open (0–16):** cold open on the old SIS sign-in failing.
2. **Magnet (16–24):** portal fragments magnetise together in segments of several blocks at once, smoothly, then snap home. The interior blocks break into debris that spirals into the portal.
3. **Isko (24–32):** he spawns as a fireball, cools to an obsidian ball, then pops into the pixel Isko.
4. **Warp (32–36):** a short step through the portal, with no whiteout.
5. **iOS (36–100):** feature chapters alternate sides with smooth scroll and connecting threads. Center-and-zoom moves, and Isko comments.
6. **Rooms (100–116):** edit rooms with pixel switches flipping. An edit shown mid-animation: text morphs and recolours, and the cursor aligns to each switch.
7. **Platforms (116–132):** iOS, Mac and PC.
8. **Sync (132–148):** SIS sync.
9. **Drop (148–164):** a sudden drop into a near-silent void, then half a beat of silence.
10. **AI (164–200):** the bomb. Show how the AI works (RAG, notes into cards, all offline).
11. **Hub (200–224):** push into the portal. A stack of school "pages" comes out of the portal (32 per page), dealing and turning, then a crane out to the Philippines map. No bottom ticker.
12. **Face ID (224–244):** the Beta Pass ID with per-person pixel faces, then the waitlist, then the end card.

### Sound
- A chip-flavoured score: hook, form, intro, lift, groove, rooms, drive, build, void, bomb, anthem, outro.
- Risers into each section, impacts on the downbeats, and a tape stop into the drop.
- SFX: snaps, switches, slices, ignite, hiss, pop, card riffles.

## B. v4 "One Shape" (light product motion, 130 BPM, 7 phrases × 7 bars = 196 beats ≈ 1:30, loops)

### Direction
- Dribbble-level UI motion. One shape, never cut: every state is the same element morphing its size, radius and colour while its content swaps with a short blur.
- A cursor drives every change with real clicks and drags.
- Warm-gray canvas `#E8E5E0`, ink `#0B0B0C`, paper `#FFFFFF`, Geist only, one 1.75 px icon set.
- The camera zooms so each state fills the frame.
- The last frame equals the first, including the cursor's position (rest at 1180,640) and its zero speed.
- No `will-change` on anything the camera scales.

### UI and engines
- A new, future mobile UI, not today's app. Appealing, with few assets, and interacted with on screen.
- Engines: Remotion is the master timeline. HyperFrames renders the Isko artform clips as alpha WebM.

### Phrases
**1. Hook (b0–27):**
- "Sign in" pill → hover → click → circle spinner → "Session expired" card.
- Try again → spinner → Attempt 2, then 3.
- The cursor drags the card's corner into a phone. Splash "Int"+"Portal".
- The Island chip shows "COMP 20073 · 9 min" and pixel Isko peeks out. Today's cards grow out of each other's edges.

**2. Day (b28–55):**
- The next-class card opens into a hero (7:30 rolls in), then the day timeline is dragged.
- The free block opens into a sheet (library, review), then is dragged back down.
- The week strip is scrubbed with a stretching indicator. A class opens into a floor map.
- Line-art Isko notification: "Leave at 12:50."

**3. Grades and notes (b56–83):**
- GWA rolls 3.00 → 1.28, rows land, and the goal slider is dragged while "needed" ticks.
- The slider becomes Isko's coach card ("Aim for 1.19").
- In the notes, lines are drag-selected, "Ask Isko" appears, it becomes the command bar, and a question is typed.

**4. On-device AI (b84–111):**
- The note splits into chunks, then a meaning map: the question lands and the nearest 3 connect.
- The bar becomes the answer, streamed with citations.
- Wi-Fi is toggled off: "Offline · Isko still works."
- Then a flashcard stack fans and flips, a quiz (wrong pick, then "Why not?"), and a plan. The whole shape shrinks to a black dot.

**5. Sax solo (b112–139):**
- The dot becomes Isko: pebble, then pixel, then ASCII, then 3D obsidian.
- The cursor re-themes the phone: dark, paper, contrast, light.
- It drags the corner to tablet, then Mac, then PC, with a reflowing layout and the title "Same you, everywhere." Then back to the phone.
- A halftone Isko peeks over the edge.

**6. PUP SIS and campuses (b140–167):**
- Connect PUP SIS: 33%, 66%, Signed in. Rows sync.
- A "More campuses · soon" chip flips.
- The phone becomes the PUP tile, a stack builds (8, 16, 32), deals into an 8×4 page, and pages flip (64, 96, 100+): "Universities and colleges, public and private. Not connected yet."
- The camera dives into the PUP tile.

**7. Waitlist and loop (b168–195):**
- The tile becomes the Beta Pass. Six pixel faces land, then the EARLY ACCESS stamp.
- The email is typed ("you@school.edu.ph"), then Join → spinner → "You're in."
- Wordmark "IntPortal · Step through." Pixel Isko winks.
- The card becomes the "Sign in" pill again, the cursor glides home, and the film loops.

### Music (ElevenLabs composition plan, 7 sections of 12.92 s, 130 BPM)
- intro → groove → build → peak → **tenor sax solo** over a stripped groove → full band with sax answers → outro that resolves into the intro so it loops.
- UI SFX on every cursor event and every beat event.

## A+B. Combined cut (≈ 3:15)
1. Play **A** from Open through Hub (beats 0–224). Skip A's Face ID section, because B carries the Beta Pass, the waitlist and the ending.
2. At the end of the Hub crane-out, push back into the portal's light.
3. Hand off without a cut: the portal's light collapses into a single black pill on the warm-gray canvas, and **B** begins at "Sign in". On the handoff frame, the light and the pill share the same position and size.
4. **Music:** A's anthem runs a tape stop into one beat of silence, then B's intro at 130 BPM. Measure the beat grid separately for each half.
5. **Ending:** B's Beta Pass with the faces, then the waitlist, the wordmark and the loop back to "Sign in".
6. **QA:** check both halves plus the handoff seam.
