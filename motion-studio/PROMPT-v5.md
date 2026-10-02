# IntPortal v5: "Isko Is Everything" (full prompt)

## Where this comes from
- **Motion basis:** the 0xMovez post (https://x.com/0xMovez/status/2104216919033192746).
  - Its direction is used as pasted alongside that link: one shape that never cuts, cursor-driven, springs, a loop.
  - The post itself could not be fetched from this environment (x.com is network-blocked). Before building, paste its text or video notes, or allow x.com, so any extra detail gets folded in.
- **Changes for v5 (your notes):**
  1. Keep the motion design, but it was too plain. Add **pixel/voxel spawning with smooth transitions** and **more colour, staying on theme**.
  2. **Music** comes from a reference track. Cut the video on the beat at **130 BPM**.
  3. **Make it make sense:** Isko is the immersive guide who explains everything, and **Isko can be anything**.
- **Carried over** from the original `/goal`, v3 and v4: the story, PUPSIS + Mabini, the campus network, the pixel faces, the craft rules and the QA loop.

Paste everything below the line.

---

/goal
Use my motion showreel skill to make a 1:30 launch video for **IntPortal**: a portfolio-grade piece that is unmistakably IntPortal in branding, typography, colour, pacing and energy. Bring a new vision for the app. Impress me.

## 1. The idea (why it makes sense)

**Isko is the one shape.** The v4 rule "one shape, never cut" now has a reason. The shape that morphs through every state *is* Isko, IntPortal's AI, literally becoming each part of the app while he walks you through it.
- He becomes:
  - the Sign-in button
  - the Island chip
  - the class card
  - the grade chart
  - the slider knob
  - the note
  - the meaning map
  - the Wi-Fi switch
  - a flashcard
  - the phone, then the Mac, then the PC
  - the PUP tile
  - the Beta Pass
- Whatever he is, he keeps **two small eyes** (a pair of 6 px rounded bars) and his **gold spark**, so you always know it's him. The eyes blink, glance at the cursor, squint when he thinks, and go flat when something fails.
- **He explains as he goes.** The voiceover is Isko speaking in the first person: warm, short, never bragging ("Hi, I'm Isko." / "Let me get you to class." / "I read your notes, right here on your phone.").
- On-screen captions are his asides: one short line per state, set small, next to him, never a centered title.
- **"Isko can be anything"** is the throughline and the payoff. The pitch "your personal AI portal for every campus" is never said outright; the film shows it.

## 2. Look

### 2.1 Base (from the post's direction)
- Dribbble-level UI motion.
- **One shape, never cut:** every state is the same element morphing its size, radius and colour while its content swaps with a short blur.
- **A cursor drives every change** with real clicks and drags.
- **The camera zooms** so each state fills the frame.
- **Springs everywhere,** with a tiny overshoot at most.
- **The last frame is the first frame,** so it loops (including the cursor's position and speed).

### 2.2 More colour, on theme
| Role | Colour |
|---|---|
| Canvas | warm gray `#E8E5E0` |
| Ink | `#0B0B0C` |
| Paper | `#FFFFFF` |
| Chapter accent: PUP maroon | `#7A1128` |
| Chapter accent: Isko gold | `#F5B227` |
| Chapter accent: portal violet | `#8663A8` |

Plus each accent's 12% tint.

**Accent rules:**
- One accent leads each phrase. It colours Isko, the active element and that phrase's pixel/voxel spawns.
- Accents cover at most ~15% of any frame. UI chrome stays ink and paper.
- No gradients on UI chrome. Colour changes are spring-driven fills, never fades.
- Type: **Geist** for UI and display, **Geist Mono** only inside pixel/ASCII moments. One 1.75 px icon set.

### 2.3 Pixel/voxel spawning, with smooth transitions (the new signature)
**Spawn:**
- Anything new arrives as **pixels or voxels first**:
  - a coarse grid of blocks pops in on the 8th-note grid in a seeded order
  - each block springs from 0 to full scale
- Then it **resolves**: block size steps 16 → 8 → 4 → 1 px over one beat while it cross-swaps into the crisp vector UI.
- The result is pixel-born and smooth-finished.

**Voxels (3D):**
- three.js InstancedMesh cubes build objects in depth: Isko, the phone, campus buildings, school tiles. They drop in layer by layer on the beat.
- Then an orthographic dolly flattens them into the 2D UI, so the handoff has no cut.

**Exit:**
- The reverse: crisp, then mosaic, then blocks that get **absorbed into Isko** (they fly into him on springs). He literally takes things in and turns them into the next state.

**Restraint:**
- Pixel/voxel is the transition language, not the look. Every held state is clean, modern UI.
- A hint of pixel art, not a pixel-art film.

### 2.4 Isko's forms (each on the beat)
- **Shape-Isko** (the default: the morphing shape with eyes)
- voxel Isko
- hi-bit pixel sprite (obsidian pebble, block ears, visor with gold eyes, belly portal window, gold spark antenna, floating mitts, orbiting cube)
- monochrome line art
- ASCII
- faceted 3D obsidian
- halftone

**Banned:**
- bouncy easing, particle bursts, glows on UI chrome, gradients on UI chrome
- centered title on a gradient, everything fading in, corner labels and frame borders
- mismatched icon strokes, dead time, anything that looks like a template

## 3. Music: reference-driven, on the beat, 130 BPM
**Input:** the reference track (to be supplied).

**Analyse it** with librosa:
- tempo (target **130 BPM**)
- downbeats
- section map (intro / groove / build / peak / solo / full / outro)
- kick and snare pattern
- energy curve
- key

**Make the score:**
- If the reference is licensed for use, cut to it directly. Otherwise generate a new track that matches its structure, groove and energy:
  - ElevenLabs Music composition plan, 7 sections × 7 bars at 130 BPM.
  - Section 5 is a featured solo (sax, unless the reference suggests another lead).
  - The outro resolves into the intro so the video loops.
- Fit the track to exactly **196 beats = 90.46 s**.

**Then:**
- Measure the beat grid into `beats.json`. The **video is cut to the measured beats**:
  - every morph starts on a beat
  - pixel spawns land on 8th notes
  - voxel layers land on 16ths in the build
  - camera moves land on bar lines
  - accent colour swaps land on the downbeat of each phrase
- **Something happens on every beat.**
- **SFX:** UI clicks, drag ticks and toggles synthesized in code, plus a soft "tick-tick-tick" for pixel spawns and a low "thup" when voxels land, pitched to the track's key.
- **Voice:** **Isko**, one young, warm, natural voice (ElevenLabs or Fish Audio), placed on beats. The music ducks under it.
- **Loudness:** −14 LUFS integrated, ≤ −1 dBTP.

## 4. Beat sheet (130 BPM · 7 phrases × 7 bars · b = beat, 0–195)

| Phrase (beats) | Accent | Isko becomes… | What happens on the beat | Isko says |
|---|---|---|---|---|
| **1. Hello (b0–27)** | violet | voxel Isko → pill | **b0–3:** voxels pop in on the 8ths and build Isko in 3D. **b4:** an ortho dolly flattens him into the "Sign in" pill (eyes stay). **b5–11:** cursor clicks, spinner, "Session expired": his eyes go flat, attempt 2 then 3. **b12–15:** the cursor drags his corner, and he stretches into a phone. **b16–27:** splash, the Island chip, Today cards pixel-spawn and grow out of each other's edges. | "Hi, I'm Isko." / "That's the old sign-in. Let me fix that." / "Here's your day." |
| **2. Your day (b28–55)** | gold | the Island, then the class card, then the timeline | The class card opens into a hero (7:30 rolls in). The timeline is dragged. The free block opens into a sheet (library, review). The week strip is scrubbed. A class opens into a **voxel building** that flattens into a floor map with a route. Line-art Isko: "Leave at 12:50." | "Class in nine minutes. Room S512." / "You've got an hour free." |
| **3. Grades (b56–69)** | maroon | the chart, then the slider knob, then the coach | The GWA rolls 3.00 → 1.28 as grade rows pixel-spawn. The cursor drags *Isko-as-knob*, and the "needed" value ticks. He becomes the coach card: "Aim for 1.19." | "Grades are in." / "Here's what you need." |
| **4. Notes + AI (b70–111)** | violet | a note, then the meaning map, then the answer | **Notes:** lines are drag-selected, and Isko pops up as "Ask Isko". **RAG, shown literally:** the note **breaks into voxel chunks** that fly into Isko's belly window; inside, they become dots on a meaning map; the question lands and the 3 nearest light up and connect; he unfolds into the cited answer. **Offline:** he flips the Wi-Fi switch off himself, "still works." **Then:** answer → flashcards that fan and flip → quiz (wrong, then "Why not?") → plan. He shrinks to a dot. | "I read your notes, right here on your phone." / "No signal? Still works." / "Want cards? A quiz? A plan?" |
| **5. Isko can be anything (b112–139, solo)** | all three, one per bar | everything | **On the solo, one form per beat:** pebble → pixel → ASCII → 3D obsidian → halftone → voxel. **Then the themes:** he *paints* the phone dark, paper, contrast, light (the colour sweeps from his position). **Then the devices:** the cursor drags him to tablet, Mac, PC ("Same you, everywhere"), and back. | "I can be anything you need." / "Make it yours." / "Phone, Mac, PC." |
| **6. PUP → every campus (b140–167)** | maroon → gold | the PUPSIS button, then the PUP tile, then the network | Connect PUPSIS: 33%, 66%, signed in, rows sync. A **"Mabini · next"** chip grows from his side and flips. He becomes the PUP tile. **Voxel campuses** of the famous PH public universities spawn around him, linked by thin light paths (a network, a friendly rivalry), then a stack becomes pages of 100+ schools: "public and private, not connected yet." The camera dives back into PUP. | "Works with PUPSIS. Mabini's next." / "Someday, every campus." |
| **7. Step through (b168–195)** | gold → violet | the Beta Pass, then the wordmark, then the pill | He becomes the Beta Pass. Six student faces **spawn pixel by pixel**, one per beat, then the EARLY ACCESS stamp. The email is typed, then Join → "You're in." Wordmark "IntPortal · Step through." He winks. He folds back into the "Sign in" pill, and the cursor glides home. **Loop.** | "Beta's opening soon. Save your spot." / "Step through." |

**Shared content:**
- **Students:** Migs, Aya, Jun, Noor, Paolo, Tala (20×24 pixel faces built from traits).
- **Schools (names only, no seals):**
  - majors: UP, PNU, TUP, UST, DLSU, Ateneo, FEU, Mapúa, BatStateU, CvSU, BulSU, SLU, WVSU, USC, CTU, MSU
  - plus 135 more
  - PUPSIS is the only live one.

## 5. Build and render rules
- **Engines:** Remotion is the master timeline (`useCurrentFrame`, so every frame is a pure function of time). HyperFrames renders the 3D/voxel/pixel/ASCII/halftone clips as alpha WebM on the same beat grid.
- **Motion primitives:**
  - Closed-form springs (k 170, d 26).
  - `track(t, keys)`: one spring per target change, never restarted.
  - `indicator()`: lead edge stiff, trail edge soft.
  - `swapAlpha()`: swapped text gets its own enter and exit timing.
  - `loopT()` wraps time.
  - New: `mosaic(t, at)` for the block size 16 → 1, and `spawnOrder(seed)` for seeded block and voxel order.
- **Determinism:**
  - No CSS transitions, timers, `requestAnimationFrame` or `Math.random` (use mulberry32 or a hash).
  - No `will-change` on anything the camera scales.
- **Output:** 1920×1080, 60 fps, H.264 yuv420p CRF 16. Plus a share encode under 30 MiB.

## 6. QA loop (before showing me anything)
1. Render one frame per beat (196) as a contact sheet and look at it.
2. Also run a frame-to-frame motion scan for pops and whip pans.
3. Score 1–10 on:
   - hook in the first 2 s
   - phone-size readability
   - motion quality
   - colour (on theme, ≤15% accent)
   - variety (forms and spawns)
   - **Isko clarity** (is it always obvious he is the shape and what he is explaining?)
   - brand accuracy
   - sound sync (onsets within 1 frame of the measured beats)
   - loop seam (first and last frames pixel-identical)
4. Fix the 3 worst problems. Repeat until every score is 8+. Only then do the full render.

## 7. Inputs needed before building
- **The reference track,** or a link to it. Say whether it's licensed to use directly.
- **The 0xMovez post's text or video notes,** if anything in it should change the above (x.com is blocked here).
- **Network access** to `api.elevenlabs.io` (or Fish Audio) and the API key as an environment variable, for the music and Isko's voice.
