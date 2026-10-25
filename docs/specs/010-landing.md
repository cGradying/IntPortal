# 010 Landing

**Status:** draft

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

Shipped in `crates/intportal-tiles` (the scene), `PortalStage.svelte` and `lar/LarFlight.svelte`: C1–C15, C17–C19, C22–C25. Next: the lift (C16), C18c and the dive (C26–C34).

**Fit.** The portal takes whatever height the form leaves and picks the largest whole-pixel tile pitch that fits the 12 × 16 grid with a tile of margin, so it stays crisp and centred on every phone's aspect ratio.

**Frame**

- **C1.** The frame is 24 blocks, 6 wide by 8 tall, one block thick, like a Nether portal. In tetromino terms: I, L and J pieces.
- **C2.** Each block is 2 × 2 tiles, giving a 12 × 16 tile grid. At 1× a tile is 11 px on a 14 px pitch.
- **C3.** Tiles are flat squares with gaps on a black void, in four obsidian tones. The inner edge is one tone darker. No texture, grain, glyphs, floor or shaders.

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
- **C13a. The hub.** The caption under the portal names the school and opens the hub, a sheet listing every school the core knows (about 100: PUP's portals, then the state universities and colleges in `crates/intportal-core/src/schools.rs`, each derived from one base colour). Search matches the short name, the school and the region, ignoring case, spaces and accents. Without a search it shows the student's recent picks (five, kept on the phone), then their region, then A–Z by school with a letter rail to jump. Each row has a tiny portal in the school's ramp, its short name, its full name and Ready or Soon. Picking a school closes the hub and turns the orbit to it; a pick more than three portals away warps to three short and springs the rest, streaking the stars.
- **C14.** A portal that is not ready shows "Opens soon" and the school's name in place of the form, and cannot be stepped into. The card keeps its height so the portal above never jumps.
- **C15.** SIS and Mabini are ready; the state-university placeholders show "Opens soon" ([012](012-portals.md) C2, C12). The carousel is locked while signing in and once signed in.

**Layout**

- **C16.** During the intro the portal fills the screen. It then lifts and shrinks to the top third as the form rises.
- **C17.** The portal holds still while a form field has focus.

**LAR**

- **C18.** Once the portal is built, a fire flares up just below its frame, in the portal's own ramp, and LAR comes out of it over 1.1 s, resolving from coarse blocks into his pixel sprite as the fire burns out round him ([reference](reference/prototypes/lar-sheet.html)). He is the same sprite as everywhere in the app (`lar/sprite.ts`, drawn by `drawLar` at 2 CSS px per art pixel), still the obsidian LAR but with a hint of the selected portal's colours (full portal colours in his rim light, cube, swirl and fire), and his state follows what he and the student are doing: fly while he moves, think while signing in, error on a failed sign-in, happy once signed in or when tapped, sleep while the student types or after he has rested a while. Every change of state eases. He then flies round the portal on his own (`lar/wander.ts`: seek, arrive and wander, picking among orbit, drift, peek, approach and rest at random, weighted by what the student is doing). The selected portal and the neighbours in view are solid to him: he never overlaps a block. The landing reserves air round the frame for this, most of it below.
- **C18a.** LAR has no fixed line on the landing. He greets the student (by time of day) the moment he lands out of the fire. Every 7–15 s he says a short Taglish line about the app, the portal on screen or the time of day (`lar/lines.ts`), never one of his last six, in a bubble that follows him, which grows out of his side in four pixel steps, types the line out with a blinking caret (about 35 characters a second) and shrinks away again (screen readers get the whole line at once; with Reduce Motion it just appears); he is quiet while a field has focus. Tap him and he answers at once. Sign-in errors and success get a line straight away; the error itself is still shown in the form.
- **C18b. In the app.** Once IntAssis is added, the way into LAR's chat is the cube he holds, floating over the page with nothing round it. Tapping it flies the cube up into the chat, where LAR comes out of his fire round it, waves and types his hello; closing sends him back into the cube and the cube back to its place. In the chat he stands in a small window of his portal's colours and shows what he is doing. Wherever he appears, nothing round him clips his cube, mitts or glow.
- **C18c. Hands never teleport.** Gesture offsets (wave, point, thumbs, cheer) and mitt changes go through the same eased rig as his body. No mitt moves more than one art pixel between two frames at 60 fps. The wave's swing ramps in and out over 0.2 s instead of starting at full amplitude. A mitt changes its shape (open, thumb) only once it has settled within one art pixel of its target.
- **C19.** LAR's mood follows the stage as today: open at rest, focus while typing or connecting, wow on an error, happy once signed in.

**The dive (replaces the morph)**

Decided in grilling, 2026-10-25 ([plan](PLAN-dive-environment.md)). The dive is the loading screen on every launch. It supersedes the 2026-10-22 decision that a signed-in launch opens straight to Today.

- **C20.** *Removed* (2026-10-25). The tile morph into the Up next card, the tab icons and the dot grid is retired. The dive replaces it.
- **C21.** *Removed* (2026-10-25). The "fourth dimension" morph prototype is retired with C20.
- **C26. Launch, signed in.**
  - The app opens on the void with the student's own portal. It builds and dives at once, with no form and no Step through.
  - The cached snapshot loads and adopts while the dive runs, never after it. The dive ends at the later of 0.6 s and data ready.
  - If data is still loading after the dive, the tunnel keeps swirling. At 3 s it enters Today with whatever is cached, and the sync carries on behind.
- **C27. First sign-in.**
  1. After a successful sign-in, Step through shows as today.
  2. Tapping it starts the full dive, about 1.6 s.
  3. LAR says "Ayos!" and flies to the portal's mouth (0–0.4 s).
  4. The camera dives through the frame into the motif tunnel (0.4–1.2 s).
  5. The dither hands over to Today (1.2–1.6 s).
- **C28. LAR leads.** LAR stays in front of the tunnel the whole way, ahead of the camera and never behind a tile. He shrinks toward the mouth and lands as the cube at the orb's spot on Today.
  - If IntAssis is not added, he lands nowhere and simply fades out with the dither.
  - The mockup decides between two variants: "he leads" (he stays a sprite until the dither) or "he folds" (he becomes his cube at the mouth).
- **C29. Dither hand-off.**
  - The last 0.3 s is a 4 × 4 Bayer dither from the tunnel to Today, 8 steps, drawn in the scene.
  - The tunnel's last frames shift toward the ground colour of the room the student lands in, so a Day room never comes out of black.
  - There is no brightness or saturation filter on the hand-off.
- **C30. Today arrives.** Today's cards rise 8 px and fade in over 0.32 s, top to bottom, 40 ms apart, with Up next first. The tab bar and header are present from the first frame.
- **C31. Haptics.** One light tick when the dive starts, and one soft thud on the reveal. They follow the haptics setting.
- **C32. Reduce Motion.** No portal and no dive: launch and Step through go straight to Today with a 0.2 s cross-fade in the room's ground colour.
- **C33. No switch.** There is no "Play portal on open" setting. The dive costs at most 0.6 s over loading on a normal launch, and the scene stops drawing and frees its canvas as soon as Today shows.
- **C34. Signed out.** A launch with no login, or one whose adoption fails, lands on the landing and form as today.

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
| C16–C19 | screenshot on iPhone 18 Pro and 17e |
| C18c | `vitest lar/sprite.test.ts`: `c18c_mitts_move_at_most_one_pixel_per_frame` across every gesture and mood switch |
| C26 | vitest `dive.test.ts`: `c26_dive_ends_at_later_of_min_and_ready`, `c26_dive_caps_at_3s`; screen recording on 18 Pro and 17e |
| C27–C29 | `cargo test -p intportal-tiles`: dive frames at fixed `t` (tunnel order, Bayer step count, last frame equals room ground); recording |
| C30 | vitest: stagger delays; recording |
| C31 | `cargo test`: haptic events at dive start and reveal |
| C32 | screenshot with Reduce Motion on: no canvas in the DOM |
| C33 | review: no setting; canvas removed after reveal |
| C34 | vitest on the launch state |
| C22–C23 | measured fps on the 17e, reported in the PR |
| C24 | review: no three.js in `package.json`; bundle size reported |
| C25 | `cargo test`: same input gives the same tiles |

## Open questions

- C28: whether LAR leads as a sprite or folds into his cube at the mouth. The Step 3 mockup decides.
- Whether LAR's two lines are kept as they are.
