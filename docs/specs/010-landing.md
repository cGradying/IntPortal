# 010 Landing

**Status:** shipped (2026-11-10). Every criterion is built; C20 and C21 are removed.

## What changes for the student

The first screen becomes a calm, low-resolution portal made of flat square tiles on a black void. It builds itself in about half a second, reacts while the app connects, and opens when the SIS is ready. Every launch dives through the portal into Today, and that dive is the loading screen. LAR stays as the voice above the form.

## Direction and references

A minimal grid of flat tiles with gaps, in the spirit of three references: a butterfly beside its dot-matrix twin, earbuds drawn as cross-stitch, and a still from Nothing's Playground film (named in [reference/README.md](reference/README.md)). No texture, grain, glyphs, floor or shaders. The portal faces the viewer head-on. Visual reference: [portal-v8.html](reference/prototypes/portal-v8.html). Decisions: [ADR 0004](../adr/0004-landing-renders-in-rust-wasm-tiles.md).

## Keep

- LAR as the app's voice, with his moods and gestures (`src/lib/lar/`).
- Step through for a returning student.
- The one gold action button.
- Haptics for the build, the open and failure (`src/lib/haptics.ts`).
- The sign-in form's fields ([011](011-login.md)).

Retired by the user's direction (grilling, 2026-10): the three.js scene (`portal3d.ts`), the pentomino frame (`pentomino.ts`), the swirl-as-3D and the three **stones** (Schedule, Grades, Study) that LAR pulled out. **The stones are retired** (decided 2026-10-11; the user left the call to the UI engineer). The tab bar and Today already name those sections, and the new landing is about the portal and the form.

## Behaviour

Shipped in `crates/intportal-tiles` (the scene and the dive), `Landing.svelte`, `PortalStage.svelte`, `PortalPeek.svelte`, `Dive.svelte`, `Greeting.svelte`, `PortalHub.svelte`, `MiniPortal.svelte` and `lar/LarFlight.svelte`: C1–C19, C22–C44.

**Fit.** The portal takes whatever height the form leaves and picks the largest whole-pixel tile pitch that fits the 12 × 16 grid with a tile of margin, so it stays crisp and centred on every phone's aspect ratio.

**Frame**

- **C1.** The frame is 24 blocks, 6 wide by 8 tall, one block thick, like a Nether portal. In tetromino terms: I, L and J pieces.
- **C2.** Each block is 2 × 2 tiles, giving a 12 × 16 tile grid. At 1× a tile is 11 px on a 14 px pitch.
- **C3.** Tiles are flat squares with gaps, in four obsidian tones. The inner edge is one tone darker. No texture, grain, glyphs or shaders. *Amended 2026-11-15:* the void is the app's own night ground with an unlit grid of square dots on the portal's tile pitch, so the page's dots and the frame's tiles share centres. Within four tiles of the frame the dots grow and take a tone from the school's ramp, falling off with distance. The frame's last four rows are mirrored under its foot in tiles that fade out row by row. Ground tiles (the glow, the mirror and the stars) fade by transparency, never toward black, so none of them reads as a dark square on the lit ground.

**Spawn**

- **C4.** The frame builds both ways at once, from the bottom centre up both sides, meeting at the top.
- **C5.** Each tile grows in place over 0.2 s with a slight overshoot (never past its gap): a small light core, easing through the theme accent into its own tone.
- **C6.** The whole build takes about 0.7 s, at 60 fps.
- **C7.** One haptic tick fires when the two sides meet.
- **C8.** A returning student skips the build; the frame is already standing.

**Tiles react to the stage**

- **C9.** At rest, a few tiles quietly flip tone with a short shrink.
- **C10.** While connecting, a soft accent pulse travels around the frame.
- **C11.** When the portal opens, an accent wave runs up both sides from the bottom centre and settles into a faint theme tint.

**Interior as state, drawn in the same tiles**

- **C12.** Each portal has its own interior motif ([012](012-portals.md) C11): swirl, ripple, bloom, rain, lattice or aurora. At rest the motif breathes quietly in the low tones; while connecting (signing in, loading) the interior shows warp stars; when open, a dither dissolve of about 0.7 s turns the stars into the full motif. Colours come from the portal's theme ([012](012-portals.md) C7).

**Portals carousel**

- **C13.** The portals ride an orbit like planets round a sun: the selected one faces you, centred and full size; its neighbours sit well out to the sides, smaller, higher and dimmer, and portals further round are behind, out of sight. Changing portal turns the whole orbit (about 0.7 s on a soft spring), while a faint starfield behind drifts with parallax and each star trails a tail on the side the orbit came from, brighter at the head and fading to the void, that grows and shrinks smoothly with the turning speed and retracts as the spring settles; stars fade out before they wrap the screen edge, and at rest they only twinkle (Reduce Motion: still, no tails). Swipe to turn it, with a rubber band at the ends; letting go springs to the nearest portal, and a flick moves one portal. Labelled arrows do the same without a swipe. Each snap ticks a `select` haptic. It supports N portals: only the few in view are drawn.
- **C13a. The hub (the portal wall).** *Amended 2026-11-15:* the plaque under the portal (the school's mini portal, its short name in the accent, its full name, a chevron) opens the wall, which dithers out of the plaque and back into it like LAR's chat (spec 048), and "1 of 108" is gone. Without a search the wall starts with **Open now**: the portals that work today as large cards. The region below leaves those out; A–Z keeps them. Originally: the caption under the portal names the school and opens the hub, a sheet listing every school the core knows (about 100: PUP's portals, then the state universities and colleges in `crates/intportal-core/src/schools.rs`, each derived from one base colour). Search matches the short name, the school and the region, ignoring case, spaces and accents. Without a search it shows the student's recent picks (five, kept on the phone), then their region, then A–Z by school with a letter rail to jump. Each row has a tiny portal in the school's ramp, its short name, its full name and Ready or Soon. Picking a school closes the hub and turns the orbit to it; a pick more than three portals away warps to three short and springs the rest, streaking the stars.
- **C14.** A portal that is not ready shows "Opens soon" and the school's name in place of the form, and cannot be stepped into. The card keeps its height so the portal above never jumps.
- **C15.** SIS and Mabini are ready; the state-university placeholders show "Opens soon" ([012](012-portals.md) C2, C12). The carousel is locked while signing in and once signed in.

**Layout**

- **C16.** While the frame builds, the portal stands larger (1.3×) in the middle of the screen, with no form and no school name. As the form rises it lifts and shrinks into its place above the form over 0.7 s, on the same ease. A returning student and Reduce Motion start at rest. (The 2026-10 wording said the portal fills the screen; a full-screen canvas scaled 2.5× blurs the tiles, so it stands at 1.3× instead.)
- **C17.** The portal holds still while a form field has focus.

**LAR**

- **C18.** Once the portal is built, a fire flares up just below its frame, in the portal's own ramp, and LAR comes out of it over 1.1 s, resolving from coarse blocks into his pixel sprite as the fire burns out round him ([reference](reference/prototypes/lar-sheet.html)). He is the same sprite as everywhere in the app (`lar/sprite.ts`, drawn by `drawLar` at 2 CSS px per art pixel), still the obsidian LAR but with a hint of the selected portal's colours (full portal colours in his rim light, cube, swirl and fire), and his state follows what he and the student are doing: fly while he moves, think while signing in, error on a failed sign-in, happy once signed in or when tapped, sleep while the student types or after he has rested a while. Every change of state eases. He then flies round the portal on his own (`lar/wander.ts`: seek, arrive and wander, picking among orbit, drift, peek, approach and rest at random, weighted by what the student is doing). The selected portal and the neighbours in view are solid to him: he never overlaps a block. The landing reserves air round the frame for this, most of it below.
- **C18a.** LAR has no fixed line on the landing. He greets the student (by time of day) the moment he lands out of the fire. Every 7–15 s he says a short Taglish line about the app, the portal on screen or the time of day (`lar/lines.ts`), never one of his last six, in a bubble that follows him, which grows out of his side in four pixel steps, types the line out with a blinking caret (about 35 characters a second) and shrinks away again (screen readers get the whole line at once; with Reduce Motion it just appears); he is quiet while a field has focus. Tap him and he answers at once. Sign-in errors and success get a line straight away; the error itself is still shown in the form.
- **C18b. In the app.** Once IntAssis is added, the way into LAR's chat is the crystal chip. Tapping it dithers LAR's window out of the chip (spec 048 C1–C3): the chat box is the crystal itself, and LAR is inside it (round three C2; the opening, header and steps are round four, spec 048). He comes out of his fire standing on the sky header's horizon, waves and types his hello; closing folds him back into his fire and dithers the window back into the chip. In the window he shows what he is doing, as a trace of his real steps (048 C12). Wherever he appears, nothing round him clips his mitts or glow; in the window his cube is the glass, so he is drawn without his own.
- **C18c. Hands never teleport.** Gesture offsets (wave, point, thumbs, cheer) and mitt changes go through the same eased rig as his body. No mitt moves more than one art pixel between two frames at 60 fps. The wave's swing ramps in and out over 0.2 s instead of starting at full amplitude. A mitt changes its shape (open, thumb) only once it has settled within one art pixel of its target.
- **C19.** LAR's mood follows the stage as today: open at rest, focus while typing or connecting, wow on an error, happy once signed in.

**The dive (replaces the morph)**

Decided in grilling, 2026-10-25 ([plan](PLAN-dive-environment.md)). The dive is the loading screen on every launch. It supersedes the 2026-10-22 decision that a signed-in launch opens straight to Today.

- **C20.** *Removed* (2026-10-25). The tile morph into the Up next card, the tab icons and the dot grid is retired. The dive replaces it.
- **C21.** *Removed* (2026-10-25). The "fourth dimension" morph prototype is retired with C20.
- **C26. Launch, signed in.**
  - The app opens on the void with the student's own portal. It builds and dives at once, with no form and no Step through.
  - The cached snapshot loads and adopts while the dive runs, never after it. The dive ends at the later of 1.8 s and data ready: the frame builds over 0.45 s, the camera dives through two changes of form over 0.95 s, and the field lands over 0.4 s. (Slowed on 2026-11-10 at the user's ask, from 0.6 s, which read as a flash: "the already logged one its too fast".)
  - If data is still loading after the dive, the tunnel keeps changing form at full screen (C29a). At 3 s it enters Today with whatever is cached, and the sync carries on behind.
- **C27. First sign-in.**
  1. After a successful sign-in, Step through shows as today.
  2. Tapping it starts the full dive, about 2.4 s (picked in round six; it was 1.6 s).
  3. LAR says "Ayos!" and flies to the portal's mouth (0–0.42 s).
  4. The camera dives into the mouth through three forms of the tunnel, in speed-ramped surges (0.42–1.92 s).
  5. The field lands on Today (1.92–2.42 s).
- **C28. LAR leads (picked).** LAR goes in ahead of the camera, shrinking toward the centre of the tunnel, and is gone into it before the field lands. The cube is already at its spot on Today. He stays a sprite the whole way.
- **C29. One field, void to Today** (revised 2026-11-04, picked in round six).
  - The scene is one grid of tiles on the same pitch as Today's dot grid. At rest the void is that grid dimmed to dots, over pools of the school's ramp that drift and surge with the tunnel. The portal's frame is dots swelling into tiles, and its light spills onto the dots near it, with falloff.
  - The portal's mouth holds the same grid at 1/4.5 of its pitch. The dive is a real camera move: the camera zooms about the mouth, the frame's tiles grow and rush past the edges, and the camera stops when the mouth's tiles are the screen's tiles.
  - The field's last frames warm toward the ground of the room the student lands in, so a Day room never comes out of black.
  - Arrival runs from the centre out on a glowing front. Each tile flares and swells 28% as the front reaches it, shrinks to a dot of Today's dot grid and lifts off in a 4 × 4 Bayer dither, leaving a glint that fades. As the last tiles go, one ripple runs through Today's dot grid.
  - There is no brightness or saturation filter on the hand-off.
  - Prototype: `reference/prototypes/mockups.html`, round six.
- **C29a. The tunnel shader** (added 2026-11-04). One function per tile, in the same tiles as everything else.
  - **Forms:** spiral arms, round rings, a square corridor, petals, polar checks and plasma. Each gives a brightness for a cell. They blend as brightness, so one shape melts into the next, and each play takes a different order. Angles only take whole multiples, so no form has a seam.
  - **Look, shared by every form:** every dark part glows at its edge, and the far end is a dark eye in a ring of light. Brightness lands on the school's ramp through a 4 × 4 Bayer dither. There are eight colours a frame.
  - **Speed ramp:** shader time and the camera both surge through each change of form and coast between them. A first sign-in has three changes, a launch has two, and slow data keeps changing every 0.7 s.
  - **Cost:** per-cell geometry is computed once into a table, so a tile costs a few cosines. Target: under 2 ms a frame in Rust on the iPhone 17e.
- **C30. Today rises once** (revised 2026-11-09, the user's pick in round three). Today is fully laid out under the hello from the start of arrival. It rises once, block by block, as the hello leaves (C35), and nothing else on it moves. This replaces the 2026-11-03 rule that nothing on Today rises after the field lands.
- **C31. Haptics.** One light tick when the dive starts, and one soft thud on the reveal. They follow the haptics setting.
- **C32. Reduce Motion.** No portal and no dive: launch and Step through go straight to Today with a 0.2 s cross-fade in the room's ground colour.
- **C33. No switch.** There is no "Play portal on open" setting. The dive costs at most 1.8 s over loading on a normal launch, and the scene stops drawing and frees its canvas as soon as Today shows.
- **C34. Signed out.** A launch with no login, or one whose adoption fails, lands on the landing and form as today.
- **C35. The hello** (added 2026-11-09, the user's ask). On every way in (launch signed in, and Step through), the dive lands on the room's ground and the day says hello: "Good afternoon." then "Today is Monday, November 9.", each word fading up out of a soft blur, slowly, like a new device saying hello. It holds (about 1.5 s in all), then lifts away as Today rises block by block (C30). Picked 2026-11-09, round three: A, two lines, Today rises. The greeting is no longer at the top of Today; the date is Today's title.
  - The hello waits for Today's data (not only Today mounted), so Today never rises as a skeleton. It waits at most 3 s from the dive's landing; past that Today rises with what is cached and the data follows, as in C26. A tap skips the rest of the hold.
  - Reduce Motion: no dive, the hello cross-fades in and out (C32's cross-fade becomes this).

**Touch and the peek** (added 2026-11-10, the user's ask for an "interactive and sensical landing page"; picks: peek through the portal, the portal and LAR react to touch, a one-line pitch)

- **C36. The portal and LAR answer a touch.**
  - A tap on the selected portal sends a ring out from the finger at 20 tiles a second, across the frame and the interior alike: each frame block dips and lights in the accent as it passes, and the interior brightens up to three steps. It fades over 1.2 s. One `select` haptic. A tap is a touch that moves under 10 px and lifts within 0.4 s, so swipes still turn the carousel.
  - LAR can be picked up and carried: he follows the finger closely, leaning into the pull, and when let go he says a "drop" line and wanders on. A press that barely moves is still a tap (C18a).
  - Reduce Motion: no ring, and LAR can't be carried.
- **C37. Peek through the portal.**
  - After the ring has run 0.38 s, a view opens out of the portal's mouth in six pixel steps, larger than the portal, and shows what is on the other side, with sample data marked "Sample": Today (the next class and a due), Schedule (a week of blocks), Grades (this term's average and three subjects) and Study (a flashcard and cards due). LAR names each page in a line inside the view.
  - Each page holds 4.5 s, then turns; a tap on the view turns it at once; the last page closes it. A tap on the void round the portal, a focused field, a swipe to another portal or Step through closes it too.
  - Until the student's first peek, a "Peek inside" button with a pixel eye sits under the portal (*amended 2026-11-15*, was a hint line); once they have peeked it leaves the screen and stays for VoiceOver and the keyboard. It is remembered on the phone.
  - The view is one button: VoiceOver reads the page's name and "Tap for the next one".
- **C38. A one-line pitch.** Under the wordmark, one line in the system face says what IntPortal does with the selected portal: "Your schedule, grades and deadlines. Works offline." (SIS), "Your eMabini courses and deadlines. Works offline." (Mabini), and "{school} is next. For now, IntPortal works with PUP." for a portal that is not ready. *Amended 2026-11-15 (second pass):* the line shows only for a portal that is not ready. For the ready portals the welcome (C42) says what the app does.

**Things to do before signing in** (added 2026-11-15, the owner's ask that the landing have functions a student can use)

- **C39. Look around.** "Look around first" sits under the welcome's Sign in (C42) and, for a portal that is not ready, in place of the form. It opens the whole app on sample data, in release builds too, with no login.
- **C40. Is the portal up?** Said only when it matters: under the portal, beside "Peek inside", the line "SIS isn't answering" (or "eMabini isn't answering") shows when the portal does not answer, and nothing shows while it does. It asks the `portal_status` command, which loads the portal's sign-in page and nothing more: no credentials, every SIS host tried at once with a 6 s limit each. The answer is kept a minute; a tap asks again. It talks only to the school's own servers.
- **C41. LAR's words never cover the frame.** His bubble goes beside him, above, level or below, else just under or over the frame: the first spot clear of every frame tile and of him. It keeps its spot while that stays clear. Right under the frame's middle, where nothing else fits, it may cover him but never the frame. When the portal at the front changes, he drops what he was saying.

**The welcome** (added 2026-11-15, the owner: "the login page is too heavy and too many things happening"; "the landing page for new user on what is the app about")

- **C42. A new student reads what the app is before any form.** The first time, under the wordmark and the portal: "Your PUP schedule, grades and deadlines, on your phone.", then three facts, each marked with one lit tile: "Works offline after one sign-in", "Your login stays on this phone", "LAR helps you study and plan". One gold button, "Sign in with SIS", and the text link "Look around first". No card, no plaque, no peek and no status: just the portal and LAR. "Sign in with SIS" brings the form in place of the welcome; Back returns to it. Once the student has asked for the form or looked around, later launches open on the form (kept on the phone).
- **C43. One thing moves at rest.** On the landing only the portal's mouth moves once the frame stands. The stars keep their own brightness and brighten and streak only while the orbit turns. The lit dots do not pulse. The app's colour pools stand still at 40 % here, so the portal is the light. LAR keeps his flight (C18).
- **C44. The form step carries the form.** Under the portal: "Peek inside" (until the first peek) and the school plaque, both as words on the ground, not boxes. Then the student number, birthdate and password, one gold Sign in, and the fine print (011 C18).

**Motion budget and renderer**

- **C22.** Motion is continuous and eased (only the three-frame pop is stepped). The build, swipes, the pulse, the opening wave and the dive run at 60 fps; at rest, 30 fps.
- **C23.** Rendering stops when the app is backgrounded.
- **C24.** The renderer is Rust compiled to WebAssembly, drawing tiles into a canvas in software. three.js, `portal3d.ts` and `pentomino.ts` are removed.
- **C25.** The scene is a pure function of time and state. A frame at time `t` is testable without a screen.

## Copy

- Wordmark: `Student IntPortal` (kept).
- LAR's lines: the pool in `src/lib/lar/lines.ts`.
- Unready portal: `Opens soon`.

## Data shape

- Scene input: `{ t, stage, portal, theme, returning, reduce, ground }` where `stage` is `forming | rest | connecting | open | diving` and `ground` is the landing room's ground colour (C29).
- Scene output: a list of tiles (`x, y, color`) per frame, plus the haptic events due in that frame.
- Replaces `landingAt` in `src/lib/landing.ts`, which stays as the Svelte-side clock until the renderer lands.

## Errors

- WASM fails to load: no portal is drawn, only the void, and the form works as usual. Sign-in must never depend on the animation. (The `.wasm` is bundled with the app, so this is a last resort, not a state to design.)
- Sign-in errors are shown by the form ([011](011-login.md)), not the portal; the portal returns to rest and LAR turns "wow".

## Motion and Reduce Motion

- Reduce Motion shows a still, open portal with no flips, pulses or waves, and skips the dive (C32).
- Haptics follow the existing setting; none fire under Reduce Motion for the build.

## Accessibility

- The canvases are decorative: `aria-hidden`. Everything they say is also in text (portal names, "Opens soon"). LAR is a button, "LAR, tap to talk"; his bubble is announced only for a tapped reply, an error or sign-in, so VoiceOver isn't flooded by chatter.
- The carousel is operable by buttons with labels, not only by swipe.
- Contrast for text over the void meets the existing landing rules in `DESIGN.md`.

## Out of scope

- Mabini's theme colours.
- Android-specific haptics tuning.

## Test map

| Criterion | Check |
|---|---|
| C1–C3 | `cargo test -p intportal-tiles`: grid size, tile count (96), tone set |
| C4–C8 | `cargo test`: tiles present at fixed `t` values; bottom-centre first; meeting haptic at the right frame |
| C9–C12 | `cargo test`: tile colours at fixed `t` per stage |
| C13–C15 | vitest on the carousel state; screenshot |
| C17–C19 | screenshot on iPhone 18 Pro and 17e |
| C18c | `vitest lar/sprite.test.ts`: `c18c_mitts_move_at_most_one_pixel_per_frame` across every gesture and mood switch |
| C26 | `cargo test`: `c26_a_launch_lasts_at_least_the_minimum_and_ends_with_the_data` (1.8 s, two forms), `c26_the_tunnel_holds_until_data_is_ready`; screen recording on 18 Pro |
| C27–C29 | `cargo test -p intportal-tiles`: dive frames at fixed `t` (tunnel order, Bayer step count, last frame equals room ground); recording |
| C30 | recording: Today's blocks rise once as the hello leaves, and nothing moves after |
| C31 | `cargo test`: haptic events at dive start and reveal |
| C32 | screenshot with Reduce Motion on: no canvas in the DOM |
| C33 | review: no setting; canvas removed after reveal |
| C34 | vitest on the launch state |
| C35 | vitest `greeting.test.ts`; screen recording: dive, hello, Today rising, no pops; a tap skips |
| C36 | `cargo test`: `c36_a_touch_rings_out_from_the_finger_and_fades`; vitest `peek.test.ts`: `c36_a_tap_is_short_and_still_a_swipe_is_not`; recording: the ring, LAR carried and dropped |
| C37 | vitest `peek.test.ts`: `c37_the_peek_shows_today_schedule_grades_study_then_closes`; recording: the view opens out of the mouth, turns, closes on a tap outside |
| C38 | screenshot at 375 by 667 and 440 by 956 |
| C3 (2026-11-15) | `cargo test -p intportal-tiles`: `c3_the_portal_lights_the_ground_near_it_and_no_further`, `c3_the_frame_is_mirrored_under_its_foot_for_four_fading_rows`, `c3_ground_dots_share_the_tiles_grid_and_grow_toward_the_frame`, `c3_the_pages_dots_line_up_with_the_portals_tiles`, `c3_the_ground_fades_by_transparency_not_toward_black`; vitest `tiles.test.ts` (alpha in `hex`) |
| C13a (2026-11-15) | vitest `hub.test.ts`: Open now first, region without repeats; screenshot of the wall |
| C39 | screenshot; review: `demo()` has no debug gate |
| C40 | vitest `portals.test.ts`: `statusChip`; `cargo test -p intportal` builds `portal_status` |
| C41 | vitest `lar/wander.test.ts`: `placeBubble` sweep over the stage |
| C42, C44 | screenshot of both steps at 390 by 844 and 375 by 667 |
| C43 | `cargo test -p intportal-tiles`: `at_rest_the_ground_and_the_stars_hold_still` |
| C16 | recording: the portal builds in the middle and lifts as the form rises |
| C22–C23 | measured fps on the 17e, reported in the PR |
| C24 | review: no three.js in `package.json`; bundle size reported |
| C25 | `cargo test`: same input gives the same tiles |

## Open questions

None. C28 was settled in round six (LAR leads as a sprite), and LAR's lines live in `lar/lines.ts`.
