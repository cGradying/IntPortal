# Dive-through launch, playful premium app, pixel calendar (spec-driven)

## Context
The app ends sign-in with a 2.6× scale and fade, then a hard swap to Today. Today has no entrance of its own. The app reads as a generic dark dashboard:
- 17 font sizes;
- Montserrat and Source Sans;
- about 175 hardcoded hex colours.

The calendar is rounded DOM blocks with no motion and no "moved" mark. LAR's hands jump when a gesture starts.

The user wants a smooth, premium and playful app with its own environment, and a calendar drawn from the reference sheet's pixel ideas. The work is spec-driven, and the user picks from mockups before anything is built.

Repo: `~/Workspaces/Personal Work/intportal-app`, from main (4016d4c, which includes #153).

## Decisions (grilled, rounds 1 to 7)
**The dive.**
- The dive is the loading screen for every launch, which replaces the 10-22 decision "a signed-in launch goes straight to Today".
- On a normal launch the portal builds and dives at once. It lasts as long as loading takes: at least 0.6 s, usually under 1 s. If loading is slow, the tunnel keeps swirling.
- After the first sign-in it is the full version, about 1.6 s, started by tapping Step through. LAR says "Ayos!" and flies to the portal's mouth first.
- Loading runs alongside the animation, never after it. The Rust tile scene draws it.
- LAR stays in the foreground and leads the way in. If the mockup shows him getting lost in the tunnel, he folds into his cube instead, and it lands at the orb.
- The "Play portal on open" switch is dropped. Reduce Motion goes straight to Today.

**Look and feel.**
- **Environment:** research what ships, then mockups decide. Rooms, the dot grid, the Today campus scene and Isko are each shown with and without, and mockups decide.
- **Versatile:** looks right in every school's colours first, then works for a glance and for dense lists, then holds up in light and dark.
- **Premium:** playful, but the play wraps the data. Motion, LAR, empty states, celebrations and haptics can be playful. Times, rooms and due dates stay calm, exact and readable at a glance. This replaces the reference sheet's "one pixel moment per screen" rule.
- **Type:** three mockups.
  - System + pixel, the primary option.
  - Geist + Pixelify.
  - Instrument Serif for titles only, with SF Pro for reading.
- **Numerals:** a hand-drawn pixel numeral set. How widely it's used (hero numbers only, or everywhere) is decided by the mockups. Pixelify is for words only.
- **Type scale:** the 7-role scale is shown next to the current one, and mockups decide.

**Feedback and calendar.**
- **Juice (Balatro feel):** mockups show the levels (subtle, medium, loud) and where the juice lives. There are no compulsion mechanics, which is my stance, recorded for the user to overrule.
- **Sound:** a tiny pixel sound kit behind a switch in You, off by default.
- **Celebrations:** one kit (tile confetti, LAR's hop, the cube sparkle). It is used only for the first sign-in, a deadline marked done, and a new grade posting.
- **Calendar:** draws on the reference sheet: stepped blocks with tile gaps, stamps (vacant, online, moved) that thunk onto a class, spring swipes and a sub-pixel now-line. Whether the views stay as they are or change is left to the mockups.
- **LAR's hands:** they are eased and never teleport. This is a bug fix.

**Process.** Audit plus a market scan, the specs, and the mockups go to the user as one review. The user picks, then I build.

Poteto principles applied:
- **Experience First.** Prototype in throwaway HTML before production code. The transitions and feedback get the polish.
- **Exhaust the Design Space.** Environment, type and juice each get 2–3 really different directions side by side.

## Step 0: write the plans down first
The user asked for this: plans first, then step by step.
- Commit this plan into the repo as `docs/specs/PLAN-dive-environment.md`, on a `docs/plan-dive-environment` branch, before any other work, so it survives the context compaction the user asked for.
- Each step below ends with a short checkpoint line appended to that file: what was done, the evidence, and what comes next.
- Steps run one at a time.

## Step 1: research and critique (read-only)
1. **Audit what ships.**
   - Facts are already gathered: the type and hex inventory, the transition timings, the calendar internals, and the motion and Reduce Motion table.
   - Add simulator screenshots of every screen in the Night and Day rooms on the iPhone 18 Pro. They stay local in `docs/review/`.
2. **Critique as a scored report**, with each finding backed by a screenshot or a line reference. The lenses:
   - UI engineering: tokens, rhythm, consistency;
   - UX: the "never miss a deadline" goal, two-tap actions, glanceability;
   - motion: pops, easing, Reduce Motion;
   - accessibility: contrast, Dynamic Type caps, 44 pt targets.
3. **Market scan**, by a background agent with web access, with its claims verified and real links only. It covers what premium and playful apps ship for type, ambient colour, pixel craft, juice and calendar grids: Structured, Fantastical, Things, Duolingo, Balatro, Arc Search and Notion Calendar.

## Step 2: specs
- **`docs/specs/010-landing.md`: C20–C21 rewritten as the dive.**
  - Covers the launch and first-sign-in timelines, the load race (the dive ends at whichever is later, the 0.6 s minimum or data ready), LAR leading or the cube fallback, a Bayer dither into Today, Today's cards rising in a 40 ms stagger, the haptics and Reduce Motion.
  - The C20 tile morph is retired. The 10-22 launch decision in spec 040 or the plan is updated to match.
- **New `docs/specs/043-app-environment.md`.**
  - Covers the environment, type roles and scale, pixel numerals, colour tokens for the night surfaces, the juice and motion tokens, the sound kit, the celebration kit and the play limits.
  - The picks it depends on stay open until the mockups are chosen.
- **New `docs/specs/044-pixel-week.md`.**
  - Covers the blocks, the stamps (including "moved"), swipes, the now-line and the Reduce Motion fix for infinite loops.
  - Each clause gets a test.
- **Spec 010 C18 (LAR):** add that gestures ease through the rig, with a 1 px per frame limit on the mitts.

## Step 3: mockups (one interactive Artifact, built with the artifact-design and impeccable skills, source in `docs/specs/reference/prototypes/`)
- **Environment:** three directions on Today, Schedule and Grades at phone size, each in Night and Day and in two school themes. Each is shown with and without rooms, the dot grid and the campus scene.
- **Type:** three directions, plus the 7-role scale against the current 17 sizes. Pixel numerals shown for hero numbers only and everywhere.
- **Juice:** subtle, medium and loud, playable. Covers the press squash, count-ups, stamp thunk plus shake, and idle sway (decorative things only, or cards too).
- **Calendar:** layout options from the reference sheet: same views restyled, plus one variant with a deadline month strip.
- **Dive:** a playable launch version and first-sign-in version, with scrub and replay, showing LAR leading and the cube fallback.

The user picks one per row, and those picks finalise spec 043, spec 044 and DESIGN.md.

## Step 4: build (after the picks), one branch and PR each, in this order
1. **`fix/lar-hands`** (can start first, since it's a bug fix). In `src/lib/lar/Lar.svelte`, the GEST offsets and thumb swaps go through an eased per-mitt spring, and the wave's amplitude ramps in and out. A `sprite.test.ts` test checks no mitt moves more than 1 sprite pixel per frame across all gesture and state switches.
2. **`ui/dive`.** The dive stage and dither in `crates/intportal-tiles`, a minimal launch path in `Landing.svelte` and `PortalStage.svelte`, and the load race in `src/routes/+page.svelte`. LAR leads, or uses the cube path through `Cube.svelte` and `AssisOrb`. Today's staggered entrance.
3. **`ui/type-system`.** Tokens in `src/lib/app.css`, the pixel numerals as a sprite set like `PixelIcon.svelte`, applied screen by screen.
4. **`ui/environment`.** Night-surface tokens, replacing the hardcoded hex in Landing, AssisSheet, PortalHub and Glance. The chosen environment.
5. **`ui/juice`.** Press, count-up, stamp, celebration and the sound kit (switch in You).
6. **`ui/pixel-week`.** `src/lib/WeekGrid.svelte` and `src/lib/screens/Schedule.svelte`.

Reuse what already exists:
- the dither code in `sprite.ts` (`mosaic`, `sheenGrid`) and the `rig()` easing;
- the `carousel.ts` spring;
- `Confetti.svelte`, the Grades `thunk` keyframe and `.notch`;
- `--font-ui` and `buzz` haptics;
- the reference sheet's stamp drawing.

## Verification
- Each PR: `pnpm check && pnpm test`, `cargo test --workspace`, and `cargo clippy -p intportal --all-targets -- -D warnings`.
- Simulator (iPhone 18 Pro and 17e):
  - the dive recorded with `simctl io recordVideo`, with frames checked for stage order, no pops and timing (launch ≥ 0.6 s and ending when data is ready, first sign-in about 1.6 s);
  - Reduce Motion on;
  - before and after screenshots in both rooms;
  - stamps and the now-line;
  - LAR's gestures recorded, with no jumps.
- Afterwards run `git checkout -- src-tauri/gen/apple/`. No merges without the user.

## Pause points
1. After Steps 1–3: the audit, the market scan, the specs and the mockups are delivered together, and the user picks.
2. Before any merge.

## Appendix: audit facts (2026-10-25, origin/main 4016d4c)
- **Type.**
  - Families: `--font-display` (Montserrat) ×58, `--font-body` (Source Sans 3), `--font-pixel` (Pixelify) ×16, `--font-ui` (system font) ×7.
  - Weights: 700 ×45, 600 ×24, 800 ×9, 400 ×8, 500 ×3.
  - 17 distinct rem sizes, about 24 size expressions in all.
  - Outliers:
    - `PortalStage.svelte:309` uses a fixed 22px;
    - `TabBar.svelte:50` caps at 13px while the same size caps at 20px elsewhere;
    - `PortalHub.svelte:360` caps at 16px while WeekGrid caps the same size at 18px;
    - `min(1.294rem, 29px)` shares its cap with body text, so h2 equals body at the largest text setting;
    - `+page.svelte:60` has an 11px debug `<pre>`.
- **Colour.** The rooms are night, day and maroon, in `app.css:12-86`. About 175 hardcoded hex values across 16 files.
  - CampusStrip 41 and Scene 35 (pixel-art palettes).
  - Landing 27 + 13 rgba, AssisSheet 25 + 25 rgba, PortalHub 14, Glance 13.
  - The night surfaces (`#140c16`, `#0b0710`, `#170b1a`) have no token, and the night gold is hardcoded.
- **Sign-in to Today.**
  1. `step()` (`Landing.svelte:125`) sets `.leaving`.
  2. The dock and brand fade over 0.25s.
  3. The canvas scales 2.6× over 1.1s with `cubic-bezier(0.55,0,1,0.45)` (`PortalStage.svelte:278-286`).
  4. The `landing.ts` timeline (FORM 0.9s, DIVE 1.1s) then calls `onenter()`, which sets `inside = true` (`+page.svelte:91-93`): a hard swap.
  5. `main` runs `arrive` for 0.65s from `brightness(2.2) saturate(0.4)`, and `.page` runs `in` for 0.3s (`+page.svelte:170-188`).
  6. Today has no entrance of its own.
- **Calendar.**
  - `WeekGrid.svelte`: DOM blocks at 44px per hour with rounded corners (columns 6px, blocks 5px) and no `.notch`. Vacant is opacity 0.35, online a 1px ring, and there is no "moved" mark. The now-line is 2px gold and updates every 60s. No animation and no swipe.
  - `Schedule.svelte` (day view): 12px-radius cards. Pixelify tags (Online, Vacant, Moved). Swiping changes the day after 60px with no animation. Its `rise` and `fade` keyframes are unused.
- **Reference sheet.**
  - Stamps: in person `#7a1128`, online `#1b4f99`, vacant `#765806`, rotated about -0.1 rad, in Pixelify with an ink mask.
  - A `thunk` keyframe exists (`Grades.svelte:476`, 0.55s `steps(6)`).
  - Its rules: "glance stays in Montserrat, no Pixelify on times or rooms", and "one pixel moment per screen" (retired by this plan).
- **Reduce Motion bug.** The global rule (`app.css:181-188`) sets durations to 0.01ms but leaves the iteration count alone. The infinite loops in Scene, Jeepney and Gallery keep cycling and can flicker.
- **LAR's hands.** `Lar.svelte` adds the GEST mitt offsets directly on every frame, outside `rig()`'s easing. The wave's sin swing starts at full amplitude, and "thumbs" swaps the mitt kind instantly.

## Checkpoints
- 2026-10-25 · Step 0 done. This plan was committed. Next is Step 1 (screenshots, critique, market scan).
- 2026-10-25 · Step 1 done. The simulator pass captured 17 screens in the Day and Night rooms plus the sign-in and dive recordings (local, `docs/review/dive-env/`). The scored critique is `reference/critique-2026-10-25.md` (UX 3, UI 2, motion 1, accessibility 2, environment 2; P0 is the flashbang from the void to a cream Today). The market scan is `reference/market-scan-2026-10-25.md`. Next is Step 2 (specs 010 C18 and C20–C21, 043, 044).
