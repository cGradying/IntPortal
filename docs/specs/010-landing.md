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

Retired by the user's direction (grilling, 2026-10): the three.js scene (`portal3d.ts`), the pentomino frame (`pentomino.ts`), the swirl-as-3D and the three **stones** (Schedule, Grades, Study) that LAR pulled out. **The stones are confirmed gone only when the user approves this spec.** The tab bar and Today already name those sections.

## Behaviour

**Frame**

- **C1.** The frame is 24 blocks, 6 wide by 8 tall, one block thick, like a Nether portal. In tetromino terms: I, L and J pieces.
- **C2.** Each block is 2 × 2 tiles, giving a 12 × 16 tile grid. At 1× a tile is 11 px on a 14 px pitch.
- **C3.** Tiles are flat squares with gaps on a black void, in four obsidian tones. The inner edge is one tone darker. No texture, grain, glyphs, floor or shaders.

**Spawn**

- **C4.** The frame builds both ways at once, from the bottom centre up both sides, meeting at the top.
- **C5.** Each tile pops in place over three stepped frames: a small light core, then the theme accent, then its own tone.
- **C6.** The whole build takes about 0.6 s, stepped at 30 fps.
- **C7.** One haptic tick fires when the two sides meet.
- **C8.** A returning student skips the build; the frame is already standing.

**Tiles react to the stage**

- **C9.** At rest, a few tiles quietly flip tone with a short shrink.
- **C10.** While connecting, a soft accent pulse travels around the frame.
- **C11.** When the portal opens, an accent wave runs up both sides from the bottom centre and settles into a faint theme tint.

**Interior as state, drawn in the same tiles**

- **C12.** The interior shows warp stars while connecting (signing in, loading) and a swirl when open. A dither dissolve of about 0.7 s turns one into the other. Colours come from the portal's theme ([012](012-portals.md) C7).

**Portals carousel**

- **C13.** The selected portal is centred; the next is dimmed beside it, with page dots below. It supports N portals from the start.
- **C14.** A portal that is not ready shows "Opens soon" and cannot be stepped into.
- **C15.** SIS is ready; Mabini shows "Opens soon" ([012](012-portals.md) C2).

**Layout**

- **C16.** During the intro the portal fills the screen. It then lifts and shrinks to the top third as the form rises.
- **C17.** The portal holds still while a form field has focus.

**LAR**

- **C18.** LAR comes through the built portal, says one line, then stays as the voice above the form, smaller and quicker than today.
- **C19.** LAR's mood follows the stage as today: open at rest, focus while typing or connecting, wow on an error, happy once signed in.

**Sign-in morph**

- **C20.** On sign-in the portal's tiles flow into Today: the frame's tiles become the "Up next" card's frame and the tab icons; the interior's tiles become the dot grid.
- **C21.** The morph runs about 30% longer than a plain transition, as the hero moment. Its abstract "fourth dimension" animation is designed in a prototype first and added to this spec before the morph is built.

**Motion budget and renderer**

- **C22.** Intro, waves and the morph run at 30–60 fps; at rest, 12–20 fps with stepped motion.
- **C23.** Rendering stops when the app is backgrounded.
- **C24.** The renderer is Rust compiled to WebAssembly, drawing tiles into a canvas in software. three.js, `portal3d.ts` and `pentomino.ts` are removed.
- **C25.** The scene is a pure function of time and state. A frame at time `t` is testable without a screen.

## Copy

- Wordmark: `Student IntPortal` (kept).
- LAR's line on arrival and the returning-student line: kept from `Landing.svelte` until the user rewrites them.
- Unready portal: `Opens soon`.

## Data shape

- Scene input: `{ t, stage, portal, theme, returning, reduce }` where `stage` is `forming | rest | connecting | open | morphing`.
- Scene output: a list of tiles (`x, y, color`) per frame, plus the haptic events due in that frame.
- Replaces `landingAt` in `src/lib/landing.ts`, which stays as the Svelte-side clock until the renderer lands.

## Errors

- WASM fails to load: show the open portal as a still image of the same tiles, plus the form. Sign-in must never depend on the animation.
- Sign-in errors are shown by the form ([011](011-login.md)), not the portal; the portal returns to rest and LAR turns "wow".

## Motion and Reduce Motion

- Reduce Motion shows a still, open portal with no flips, pulses or waves, and skips the morph (Today appears without it).
- Haptics follow the existing setting; none fire under Reduce Motion for the build.

## Accessibility

- The canvas is decorative: `aria-hidden`. Everything it says is also in text (LAR's line, portal names, "Opens soon").
- The carousel is operable by buttons with labels, not only by swipe.
- Contrast for text over the void meets the existing landing rules in `DESIGN.md`.

## Out of scope

- The 4D morph animation itself (prototype first).
- Mabini's theme colours.
- Android-specific haptics tuning.

## Test map

| Criterion | Check |
|---|---|
| C1–C3 | `cargo test -p intportal-portal`: grid size, tile count, tone set |
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
- Mabini's palette (user).
- Whether LAR's two lines are kept as they are.
- Confirm retiring the stones (user).
