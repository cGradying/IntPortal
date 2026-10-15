# 010 Landing

**Status:** draft

## What changes for the student

The first screen becomes a calm, low-resolution portal made of flat square tiles on a black void. It builds itself in about half a second, reacts while the app connects, and opens when the SIS is ready. Signing in morphs the portal's tiles into Today. LAR stays as the voice above the form.

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

Shipped in `crates/intportal-tiles` (the scene), `PortalStage.svelte` and `lar/LarFlight.svelte`: C1–C15, C17–C19, C22–C25. Next: the lift (C16) and the morph (C20–C21).

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

- **C13.** The portals ride an orbit like planets round a sun: the selected one faces you, centred and full size; its neighbours sit well out to the sides, smaller, higher and dimmer, and portals further round are behind, out of sight. Changing portal turns the whole orbit (about 0.7 s on a soft spring), while a faint starfield behind drifts with parallax and stretches into warp streaks; at rest the stars only twinkle. Swipe to turn it, with a rubber band at the ends; letting go springs to the nearest portal, and a flick moves one portal. Labelled arrows and page dots do the same without a swipe, and a caption names the school. Each snap ticks a `select` haptic. It supports N portals.
- **C14.** A portal that is not ready shows "Opens soon" and the school's name in place of the form, and cannot be stepped into. The card keeps its height so the portal above never jumps.
- **C15.** SIS and Mabini are ready; the state-university placeholders show "Opens soon" ([012](012-portals.md) C2, C12). The carousel is locked while signing in and once signed in.

**Layout**

- **C16.** During the intro the portal fills the screen. It then lifts and shrinks to the top third as the form rises.
- **C17.** The portal holds still while a form field has focus.

**LAR**

- **C18.** Once the portal is built, a fire flares up just below its frame, in the portal's own ramp, and LAR comes out of it over 1.1 s, resolving from coarse blocks into his pixel sprite as the fire burns out round him ([reference](reference/prototypes/lar-sheet.html)). He is the same sprite as everywhere in the app (`lar/sprite.ts`, drawn by `drawLar` at 2 CSS px per art pixel), dressed in the selected portal's colours, and his state follows what he and the student are doing: fly while he moves, think while signing in, error on a failed sign-in, happy once signed in or when tapped, sleep while the student types or after he has rested a while. Every change of state eases. He then flies round the portal on his own (`lar/wander.ts`: seek, arrive and wander, picking among orbit, drift, peek, approach and rest at random, weighted by what the student is doing). The selected portal and the neighbours in view are solid to him: he never overlaps a block. The landing reserves air round the frame for this, most of it below.
- **C18a.** LAR has no fixed line on the landing. Every 7–15 s he says a short Taglish line about the app, the portal on screen or the time of day (`lar/lines.ts`), never one of his last six, in a bubble that follows him; he is quiet while a field has focus. Tap him and he answers at once. Sign-in errors and success get a line straight away; the error itself is still shown in the form.
- **C19.** LAR's mood follows the stage as today: open at rest, focus while typing or connecting, wow on an error, happy once signed in.

**Sign-in morph**

- **C20.** On sign-in the portal's tiles flow into Today: the frame's tiles become the "Up next" card's frame and the tab icons; the interior's tiles become the dot grid.
- **C21.** The morph runs about 30% longer than a plain transition, as the hero moment. Its abstract "fourth dimension" animation is designed in a prototype first and added to this spec before the morph is built.

**Motion budget and renderer**

- **C22.** Motion is continuous and eased (only the three-frame pop is stepped). The build, swipes, the pulse, the opening wave and the morph run at 60 fps; at rest, 30 fps.
- **C23.** Rendering stops when the app is backgrounded.
- **C24.** The renderer is Rust compiled to WebAssembly, drawing tiles into a canvas in software. three.js, `portal3d.ts` and `pentomino.ts` are removed.
- **C25.** The scene is a pure function of time and state. A frame at time `t` is testable without a screen.

## Copy

- Wordmark: `Student IntPortal` (kept).
- LAR's lines: the pool in `src/lib/lar/lines.ts`.
- Unready portal: `Opens soon`.

## Data shape

- Scene input: `{ t, stage, portal, theme, returning, reduce }` where `stage` is `forming | rest | connecting | open | morphing`.
- Scene output: a list of tiles (`x, y, color`) per frame, plus the haptic events due in that frame.
- Replaces `landingAt` in `src/lib/landing.ts`, which stays as the Svelte-side clock until the renderer lands.

## Errors

- WASM fails to load: no portal is drawn, only the void, and the form works as usual. Sign-in must never depend on the animation. (The `.wasm` is bundled with the app, so this is a last resort, not a state to design.)
- Sign-in errors are shown by the form ([011](011-login.md)), not the portal; the portal returns to rest and LAR turns "wow".

## Motion and Reduce Motion

- Reduce Motion shows a still, open portal with no flips, pulses or waves, and skips the morph (Today appears without it).
- Haptics follow the existing setting; none fire under Reduce Motion for the build.

## Accessibility

- The canvases are decorative: `aria-hidden`. Everything they say is also in text (portal names, "Opens soon"). LAR is a button, "LAR, tap to talk"; his bubble is announced only for a tapped reply, an error or sign-in, so VoiceOver isn't flooded by chatter.
- The carousel is operable by buttons with labels, not only by swipe.
- Contrast for text over the void meets the existing landing rules in `DESIGN.md`.

## Out of scope

- The 4D morph animation itself (prototype first).
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
| C20–C21 | screenshot sequence; blocked on the prototype |
| C22–C23 | measured fps on the 17e, reported in the PR |
| C24 | review: no three.js in `package.json`; bundle size reported |
| C25 | `cargo test`: same input gives the same tiles |

## Open questions

- The 4D transition prototype (Head).
- Whether LAR's two lines are kept as they are.
