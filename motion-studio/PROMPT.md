# IntPortal launch film: combined prompt

One paste-ready prompt that merges every brief so far:
- **The original `/goal` brief (v1).** It is the base layer and applies to every cut.
- **v2 and v3 revisions,** which became **Film A, "Step Through"**: a dark pixel-portal world, 1:56 at 128 BPM.
- **v4,** which became **Film B, "One Shape"**: light monochrome product motion, a 1:30 loop at 130 BPM.

Where a later brief changed something from the original, the cut's own section says which version wins. The changes are listed in §0.4.

Paste everything below the line and set `CUT`:
- `A` for Film A only
- `B` for Film B only
- `A+B` for one extended film in which A steps through the portal into B

---

/goal
Use my motion showreel skill to make a launch video for **IntPortal**. It should feel like a portfolio-grade piece from the best motion designer in the world, and be unmistakably IntPortal in branding, typography, colour, pacing and energy. Bring a new vision for the app. Impress me.

**CUT = A+B**

## 0. Base brief (applies to every cut)

### 0.1 Research
- Scrape my repos for product details, features and UI:
  - https://github.com/cGradying/IntPortal
  - https://github.com/cGradying/intportal-app
  - https://github.com/cGradying/intportal-web
- Use https://streamable.com/46dlwp for structure only; do NOT copy it.
- Extra references, for feel only:
  - https://x.com/achxvi/status/2103918792845963545
  - https://x.com/himanshutwtxs/status/2103495232637882858
  - https://x.com/0xMovez/status/2104216919033192746

### 0.2 Concept
- **Pitch:** "your personal AI portal for every campus." Keep it subtle, not cheesy, never bragging.
- It should feel like a new startup with its own niche: a fresh animation style, not the reference's look.
- **Immersive:** the viewer feels they are actually using the app. Do a round trip through the iOS app, its themes, and every other platform (iOS, Mac and PC only).
- **PUP:** show IntPortal integrating with **PUPSIS**, with **Mabini** as the next step in PUP students' goals.
- **Campus network:** tease other famous Philippine public universities with their own portals, linked together (or competing) as a campus network. This is a teaser and future vision only, so highlight the main features. Also show "100+ universities and colleges, public and private, not connected yet."
- **Isko** is the mascot and personal helper. Give him better art and smoother animation (see 0.3).

### 0.3 Story, Isko, people, schools (shared)
**Story beats, in order:**
1. **The pain:** "Nine minutes to class… and you're signed out. Again."
2. **IntPortal opens:** the portal (A) or the shape (B) becomes the app.
3. **Your day:** schedule, free time, rooms.
4. **Grades:** grades land, and the app tells you what you need.
5. **AI:** notes become study material. Isko answers from your own notes, on the device and offline. The RAG pipeline is chunks, then a meaning map, then the nearest passages, then a cited answer, then cards, a quiz and a plan.
6. **Make it yours:** themes, then phone, Mac and PC.
7. **Campuses:** works with PUPSIS, Mabini next, and someday every campus.
8. **Waitlist:** a Beta Pass ID with per-person pixel faces. "Step through."

**Isko:**
- A cute, non-human portal spirit with Ember Knights energy:
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
- He comments on what the user is doing ("Leave at 12:50.", "Aim for 1.19").

**Pixel faces:**
- 10 students, 20×24 pixel portraits built from traits (skin, hair, glasses, hijab, cap, shirt): Migs, Aya, Jun, Noor, Paolo, Tala, Bea, Rafa, Kim, Lia.
- They fill the Beta Pass one face per beat, then an "EARLY ACCESS" stamp lands.

**Schools:**
- 16 majors: UP, PNU, TUP, UST, DLSU, Ateneo, FEU, Mapúa, BatStateU, CvSU, BulSU, SLU, WVSU, USC, CTU, MSU.
- Plus 135 more public and private schools.
- PUPSIS is the only live one.
- Names only: no seals and no marks.

### 0.4 What later briefs changed
| Topic | Original brief | Film A | Film B |
|---|---|---|---|
| Length | 60 s – 2 min | 1:56 | 1:30 loop |
| Colour | "more colours", one accent | PUP maroon and gold, night violet, portal light | Monochrome. Isko is the only colour. |
| Voice | one boy and one girl, Fish Audio | boy and girl | girl only, ElevenLabs |
| Music | synthesized in code | synthesized chip score | ElevenLabs Music with a sax solo |
| Campus background | new: a hint of pixel art blended with a futuristic, connected vibe; don't lean on pixel art | portal world with pixel accents | no background; warm-gray canvas |

In `A+B`, the combined film runs past the original 2-minute cap. Treat it as an extended cut, and also export a ≤ 2:00 edit (see §A+B).

### 0.5 Visuals (base)
- Faster and more eye-catching, with new UI designs.
- 3D VFX and smooth transitions.
- Generate new assets as needed.
- Something new on screen every 2 to 4 seconds. In Film B, something happens on every beat.

### 0.6 Audio (base)
- Fast, on-beat music with tight transitions.
- The voiceover must sound natural and human, with no bragging tone.
- **Fish Audio MCP** (may not be connected yet): `claude mcp add --transport http fish-audio https://api.fish.audio/mcp`
- **ElevenLabs** for Film B: read the key from the `ELEVENLABS_API_KEY` env var only, never from a file.
- **Mix:** VO ducks the music. −14 LUFS integrated, ≤ −1 dBTP true peak.

### 0.7 Setup
```
brew install node ffmpeg python   # apt on Linux
pip install numpy librosa soundfile
mkdir motion-studio && cd motion-studio && npm init -y
npm i -D playwright && npx playwright install chromium
npx skills add remotion-dev/skills
npx skills add heygen-com/hyperframes
claude plugin marketplace add buildwithhanif/claude-animation-skill
claude plugin install claude-animation@claude-animation-skill
claude --model claude-opus-5-5   # /model, effort xhigh (max for flagship)
```

### 0.8 Motion studio rules
**Render contract:**
- Every film is a pure function of time: `window.seek(t)` paints frame t. In Remotion, `useCurrentFrame()` does this.
- No CSS transitions, `setTimeout` or `requestAnimationFrame` in render mode.
- No state between frames.
- Seeded noise only (mulberry32 or hash), never `Math.random`.
- Render with `node render.mjs` (A) or Remotion (B), H.264 yuv420p, CRF 16, 1920×1080 at 60 fps.

**Motion:**
- Closed-form springs (k 170, d 26, ζ≈1), with a tiny overshoot at most.
- `track(t, keys)` adds one spring per target change and never restarts.
- `indicator()`: the lead edge is stiff and the trail edge soft.
- `swapAlpha()`: swapped text gets its own enter and exit timing, with a short blur.
- `loopT()` wraps time for loops.

**Look:**
- One display face, one UI face, one accent colour, unless the cut says otherwise.
- **Banned:**
  - a centered title on a gradient
  - everything fading in
  - corner labels and frame borders
  - glow on UI chrome
  - generic particle bursts
  - bouncy easing
  - gradients on UI chrome
  - mismatched icon strokes
  - dead time
  - anything that looks like a template

**Sound:**
- Synthesize score and SFX in code unless a track is supplied.
- Hits land on the measured beat grid (`beats.json`).

### 0.9 QA loop (before showing me anything)
1. Render one frame per beat as a contact sheet and look at it.
2. Score 1–10 on:
   - hook in the first 2 s
   - phone-size readability
   - motion quality
   - variety
   - brand accuracy
   - sound sync
   - loop seam (Film B)
3. Fix the 3 worst problems. Repeat until every score is 8+.
4. Only then do the full render.

## A. Film A: "Step Through" (dark pixel-portal world, 128 BPM, 61 bars ≈ 1:56)

### Look
- A night-violet world with three.js depth. Bloom is only on the portal light, never on UI.
- The new campus background: connected nodes and light paths with a hint of pixel art, not a pixel-art campus.
- PUP maroon and gold swirl inside an obsidian portal.
- More colours are allowed here.

### Type
- SDF morph type that morphs (never glitches) between a clean sans and a pixel font, in different sizes.
- Glyph bands scatter side by side.
- Thin geometry draws around the words: rules, squares, rings, crosshairs, corner brackets.
- Chromatic spectral edges, not rainbow colour.

### Sections (in beats)
1. **Open (0–16):** cold open on the old SIS sign-in failing.
2. **Magnet (16–24):** portal fragments magnetise together in segments of several blocks at once, smoothly, then snap home. The interior blocks break into debris that spirals into the portal.
3. **Isko (24–32):** he spawns as a fireball, cools to an obsidian ball, then pops into the pixel Isko.
4. **Warp (32–36):** a short step through the portal, with no whiteout.
5. **iOS (36–100):** a round trip through the iOS app.
   - Feature chapters alternate sides with smooth scroll and connecting threads.
   - Center-and-zoom moves, and Isko comments on what you're doing.
6. **Rooms and themes (100–116):** edit rooms with pixel switches flipping, shown mid-animation.
   - Text morphs and recolours, and the cursor aligns to each switch.
7. **Platforms (116–132):** iOS, Mac and PC.
8. **Sync (132–148):** PUPSIS sync, then a Mabini card: "next step."
9. **Drop (148–164):** a sudden drop into a near-silent void, then half a beat of silence.
10. **AI (164–200):** the bomb. Show how the AI works: RAG, notes into cards, all offline.
11. **Hub (200–224):** push into the portal. Famous PH public-university portals light up as a linked (or competing) network.
    - Then a stack of school "pages" comes out of the portal, 32 per page, dealing and turning.
    - Then a crane out to the Philippines map. No bottom ticker.
12. **Face ID (224–244):** the Beta Pass ID with per-person pixel faces, then the waitlist, then the end card.

### Sound
- **Voice:** a boy and a girl, alternating lines.
- **Score:** chip-flavoured, in sections: hook, form, intro, lift, groove, rooms, drive, build, void, bomb, anthem, outro.
- Risers into each section, impacts on the downbeats, and a tape stop into the drop.
- **SFX:** snaps, switches, slices, ignite, hiss, pop, card riffles.

## B. Film B: "One Shape" (light product motion, 130 BPM, 7 phrases × 7 bars = 196 beats ≈ 1:30, loops)

### Direction
- Dribbble-level UI motion. One shape, never cut: every state is the same element morphing its size, radius and colour while its content swaps with a short blur.
- A cursor drives every change with real clicks and drags.
- **Palette and type:**
  - warm-gray canvas `#E8E5E0`
  - ink `#0B0B0C`
  - paper `#FFFFFF`
  - Geist only
  - one 1.75 px icon set
  - Isko's gold and purple are the only colour.
- The camera zooms so each state fills the frame.
- No `will-change` on anything the camera scales.
- The last frame equals the first, including the cursor's position (rest at 1180,640) and its zero speed.
- "Use more types of artform; integrate animations if needed."

### UI and engines
- A new, future mobile UI, not today's app. Appealing, with few assets, and interacted with on screen.
- Remotion is the master timeline. HyperFrames renders the Isko artform clips as alpha WebM.

### Phrases
**1. Hook (b0–27):**
- "Sign in" pill → hover → click → spinner → "Session expired" card.
- Try again → spinner → Attempt 2, then 3.
- The cursor drags the card's corner into a phone. Splash "Int"+"Portal".
- The Island chip shows "COMP 20073 · 9 min" and pixel Isko peeks out. Today's cards grow out of each other's edges.

**2. Day (b28–55):**
- The next-class card opens into a hero (7:30 rolls in), then the day timeline is dragged.
- The free block opens into a sheet, then is dragged back down.
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
- Then a flashcard stack fans and flips, a quiz (wrong pick, then "Why not?"), and a plan. The shape shrinks to a black dot.

**5. Sax solo (b112–139):**
- The dot becomes Isko: pebble, then pixel, then ASCII, then 3D obsidian.
- The cursor re-themes the phone: dark, paper, contrast, light.
- It drags the corner to tablet, then Mac, then PC, with a reflowing layout and the title "Same you, everywhere." Then back to the phone.
- A halftone Isko peeks over the edge.

**6. PUPSIS, Mabini, campuses (b140–167):**
- Connect PUPSIS: 33%, 66%, Signed in. Rows sync.
- A "Mabini · next" chip grows from the button and flips to "100+ schools · on the way".
- The phone becomes the PUP tile. Majors' portal tiles link to it with hairline connections, then a stack builds (8, 16, 32).
- The stack deals into an 8×4 page, and pages flip (64, 96, 100+): "Universities and colleges, public and private. Not connected yet."
- The camera dives into the PUP tile.

**7. Waitlist and loop (b168–195):**
- The tile becomes the Beta Pass. Six pixel faces land, then the EARLY ACCESS stamp.
- The email is typed ("you@school.edu.ph"), then Join → spinner → "You're in."
- Wordmark "IntPortal · Step through." Pixel Isko winks.
- The card becomes the "Sign in" pill again, the cursor glides home, and the film loops.

### Sound
- **Voice:** the girl only, with short lines on beats.
- **Music:** an ElevenLabs composition plan of 7 sections × 12.92 s at 130 BPM:
  - intro → groove → build → peak
  - **tenor sax solo** over a stripped groove
  - full band with sax answers
  - an outro that resolves into the intro so it loops
- **SFX:** UI sounds on every cursor event and every beat event.

## A+B. Combined cut
**Extended cut (≈ 3:15):**
1. Play **A** from Open through Hub (beats 0–224). Skip A's Face ID section; B carries the Beta Pass, the waitlist and the ending.
2. At the end of the Hub crane-out, push back into the portal's light.
3. Hand off without a cut: the light collapses into the black "Sign in" pill on the warm-gray canvas, and **B** begins. On the handoff frame, the light and the pill share the same position and size.
4. **Music:** A's anthem runs a tape stop into one beat of silence, then B's intro at 130 BPM. Measure the beat grid separately for each half.
5. **Voices:** boy and girl in the A half, girl only in the B half.
6. **QA:** check both halves plus the handoff seam.

**Brief-compliant edit (≤ 2:00):**
- A's Open, Magnet and Isko sections (0–32, ≈ 15 s).
- The handoff into B.
- B's phrases 1, 4, 5 and 7 in full, plus phrase 6 cut to PUPSIS, Mabini and the 100+ flip.

The total lands under 2:00.
