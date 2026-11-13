# 045 App environment

**Status:** ready to build. Every pick is settled (mockup rounds one to six).

## What changes for the student

Signing in no longer drops the student out of IntPortal's world into a generic dark or cream dashboard. The night of the landing, the hub and LAR's chat carries into the app. Type has a clear voice: one face for reading, pixel for play, and big numbers drawn in pixel numerals. Taps feel springy and satisfying, but times, rooms and due dates stay calm and exact.

## Direction and references

- [Critique 2026-10-25](reference/critique-2026-10-25.md), findings 3, 7–10, 13, 15.
- [Market scan 2026-10-25](reference/market-scan-2026-10-25.md), takeaways 1–12.
- [Reference sheet](reference/prototypes/reference-sheet.html): the stamps, the notch and the dither.
- The LAR chat stage ([010](010-landing.md) C18b) is the target mood.
- Grilling decisions, 2026-10-25 ([plan](PLAN-dive-environment.md)):
  - **Premium means playful.** The play wraps the data and never sits on it.
  - **Priority:** first every school's colours, then glance plus dense lists, then light and dark.
  - **Pixel rule.** "One pixel moment per screen" is replaced by the rule in C9.

## Keep

- Rooms as blocks of roles in `app.css`. Components read roles, never hex.
- The campus scene on Up next, the deadline list, the free-gap bands and the grade stamps.
- The gold action button. The haptics setting and `buzz`.
- Dynamic Type through `rem` with caps.

## Behaviour

**Environment**

- **C1. One night.** The void family becomes tokens in `app.css`: `--void` `#0b0710`, `--void-2` `#140c16` and `--void-3` `#170b1a`. The landing, the hub, LAR's chat and the Glance read these tokens. No hex stays outside `app.css`, except the pixel-art palettes in `CampusStrip`, `Scene`, `Jeepney` and `lar/sprite.ts`.
- **C2. The Night room (picked)** uses the void family as its ground: one night across the landing, the hub, LAR's chat and the app.
- **C3. The ground (picked).** The dot grid stays, on a living ground.
  - Two layers of soft gradient pools in the school's ramp drift against each other behind the dots and the cards, over 13 s and 17 s, alternating. Alpha stays low (0.09–0.55 by colour and room), and cards stay opaque, so text contrast does not change.
  - They move by transform only, so they run on the compositor. They pause when the app is backgrounded, and they are off under Reduce Motion.
- **C4. Each school's colours (picked).** The accent and the ground's pools come from the active portal's theme (`crates/intportal-core/src/schools.rs`), not fixed gold. Contrast stays at 4.5:1 or better, checked by test for every school. Only PUP is tuned by eye for now.
- **C4a. Campus art per school** (added 2026-11-03). The scene on Up next is drawn per school from that school's real look: its landmark, its buildings and its surroundings, in its colours. A school without its own art yet shows a shared scene. Art is drawn from photos, ready portals first. **For now only PUP is drawn** (decided 2026-11-03); the others come with the artistic pass.
- **C5. Corner roles.**
  - The pixel notch (stepped 4 px corners) is for stages and hero cards: Up next, the GPA card, sheets.
  - Dense rows and week blocks get a 4 px square-ish radius.
  - Nothing else.
- **C6. Form controls (picked)** are pixel checkboxes and switches in the room's accent, never system blue.
- **C7. The orb's lane.**
  - The cube orb never rests on top of a tappable control or a grade stamp.
  - **Decided 2026-11-03:** it stays floating at the bottom right for now, as shipped. An artistic redesign that fits the app comes later and settles the overlap.

**Type**

- **C8. Roles.** There are seven text roles, and every text style in the app maps to one of them:
  - `display`
  - `title`
  - `headline`
  - `body`
  - `label`
  - `caption`
  - `numeral`

  **Decided 2026-11-03: Pixel-bridged** (round two called it Sharp system).
  - `display`, `title`, `headline`, `body`, `caption` and `numeral`: SF Pro (`system-ui`). Titles at 800 with −0.035em tracking, headlines at 800 with −0.02em.
  - `label` (small labels, chips, day names, tab labels): Pixelify Sans at 600 with 0.06em tracking, sized so its pixel lands on the icons' pixel grid.
  - Hero numbers use the pixel numerals (C10).

  Montserrat and Source Sans stay as a **Classic** text style in You.
- **C9. The pixel rule.** Pixelify sets play and small labels only: LAR's name and bubbles, stamps, chips, section tags, day and tab labels, and celebrations. It never sets a time, a room, a date or a due item.
- **C10. Pixel numerals.** A hand-drawn numeral set (0–9, `:`, `.`, `%` and small-caps `AM`/`PM`), drawn as SVG sprites in the way `PixelIcon` is. The numerals are tabular, and their sizes snap to the art pixel. **Picked:** hero numbers only (the Up next time, GPA, Study counts).
- **C11. Scale (picked).** The current sizes stay. Each existing text style maps onto a role in C8 without changing size.
- **C12. Units.** A number and its unit always have a gap or a size change between them, so `0 days`, never `0days`.

**Juice**

- **C13. Press.**
  - Every tappable card and button squashes to 0.97 on press and springs back with a slight overshoot (the subtle level, picked).
  - The data inside a card never moves on its own.
- **C14. Count-up.** Hero numbers (GPA, the Study counts, units done) count up from their last seen value when the screen opens. They do not count up from zero on every visit.
- **C15. Stamps thunk.** Stamps land with the `thunk` (0.55 s, eased, per the Smooth Travel Rule) plus a 2 px shake of the card they land on, once per new grade or status.
- **C16. Idle sway.** Decorative pieces only (LAR, the cube, scene props). Cards and data never sway.
- **C17. Celebrations.** One kit: tile confetti, LAR's hop and a cube sparkle. It fires only on these three:
  - the first sign-in (the dive's reveal);
  - a deadline marked done;
  - a new grade posting.

  Nothing else celebrates.
- **C18. Done (picked in round four).**
  - **The sequence, about 1.1 s:** the box fills, a line strikes through the title, sparks pop, the dot grid ripples from the box, and a `DONE` stamp lands, all eased (round two, 2026-11-05). At 0.5 s the row lifts and a few tiles fall from it onto the dot grid. At 0.7 s it glides into Done. The row, the progress bar, the Done heading and LAR's card open and close over 0.36 s, so nothing jumps. The Done control is on the left of the row with the word under it, clear of the floating cube.
  - **The bar:** with more than one item, a bar of up to eight segments above the rows fills one segment per done.
  - **A run builds:** a done within 4 s of the last climbs the pentatonic scale. The first nudges, the second and third shake and show `×2`, `×3`, and from the fourth on they shake harder with a high sparkle.
  - **All clear:** the bar flashes, LAR hops with a thumbs up, confetti bursts three times, and a rising run plays.
  - **Then still.** Nothing loops.
  - **Limits:** no streak guilt, no loss framing, no hidden suspense and no random rewards. Only the detune is random.
- **C19. Sound.**
  - A tiny pixel sound kit (press tick, stamp, done, celebrate, LAR blip), under 40 KB in all.
  - A switch in You turns it on. It is off by default.
  - It respects the silent switch, and plays nothing under Reduce Motion with "Play animated effects" off.

**Moving around (picked in round six)**

- **C22. Tabs.** A pixel highlight glides under the chosen tab (0.24 s, eased), the icon hops, and the page slides 12 px toward the tab you picked.
- **C23. Scrolling.** The cube shrinks and tucks aside while Today scrolls, and returns 0.65 s after you stop.
- **C24. Up next counts.** When its minute changes, the pixel countdown drops in over 0.2 s, eased.
- **C25. Sync.** Pull past 70 px; the cube spins fast while syncing, and a `SYNCED` stamp lands with one ripple through the dot grid.
- **C26. Things grow from where they live.** A class's sheet grows out of its block and shrinks back into it (0.38 s in, 0.3 s out). The chat comes from the cube ([010](010-landing.md) C18b).
- **C27. Grades.** On first open, the GPA counts from the last seen value and the stamps thunk one by one.
- **C28. Ripples are rare.** The dot grid ripples only when something lands: the dive's end, a sync, a done.

**Motion tokens**

- **C20.** Motion goes through tokens in `app.css`:
  - `--ease` (standard);
  - `--ease-spring` (overshoot);
  - `--t-quick` 0.16 s;
  - `--t-move` 0.32 s;
  - `--t-flow` 0.36 s, for layout that opens and closes;
  - `--t-hero` 0.55 s.

  No component hardcodes another duration, except the stepped pixel animations.
- **C21. Reduce Motion.**
  - The global rule also sets `animation-iteration-count: 1`, so infinite loops stop instead of flickering.
  - Count-ups show the final value, stamps appear in place, and press keeps only a colour change.

## Copy

- The sound switch in You: `Sounds`, with the help line `Little pixel blips when you tap, mark done or get a grade. Off by default.`
- No other copy changes in this spec.

## Data shape

- A `sound` setting (boolean, default `false`) stored where the haptics setting is stored (`state.svelte.ts`).
- The last seen hero values for count-up, kept in `localStorage` under `intportal.seen`, inside `try`/`catch`.

## Errors

- If an audio file fails to load, nothing plays, nothing is shown and the switch stays as set.

## Motion and Reduce Motion

See C13–C21. Under Reduce Motion: no sway, shake, count-up, confetti or drifting backdrop. Celebrations become a static stamp and one haptic.

## Accessibility

- Every school's accent on every room's ground and card meets 4.5:1 for text and 3:1 for controls (C4).
- Pixel numerals carry the real number as text for VoiceOver (`aria-label`) and in the DOM for copy.
- Touch targets are at least 44 pt, the orb included.
- Sound is never the only signal.

## Out of scope

- The week and day calendar ([044](044-pixel-week.md)).
- The dive ([010](010-landing.md) C26–C34).
- New screens or features.

## Test map

| Criterion | Check |
|---|---|
| C1 | `vitest rooms.test.ts`: `c1_no_hex_outside_app_css` (scan `src/lib/**/*.svelte`, allow-list the art palettes) |
| C4 | `cargo test -p intportal-core`: `c4_accent_contrast_on_every_room` for all schools |
| C5, C7, C8, C11 | screenshot pass, both rooms, two schools, largest text size |
| C6 | screenshot: no system blue |
| C9 | `vitest`: `c9_no_pixel_font_on_times` (computed style on time and room nodes) |
| C10 | `vitest`: numeral sprite set complete; `aria-label` equals the text |
| C12 | screenshot of Study at zero |
| C13–C17 | recording; `vitest`: celebration fires only for the three events |
| C18 | `vitest`: `c18_combo_climbs_within_4s_and_resets`; recording of a five-item run |
| C3 | `vitest` on the CSS: transform-only keyframes, off under Reduce Motion |
| C22–C28 | recording in both rooms |
| C19 | `vitest`: off by default; muted under Reduce Motion |
| C20 | `vitest`: `c20_no_raw_durations` (scan for `s` literals outside tokens and `steps()`) |
| C21 | `vitest` on the CSS: the reduce rule sets the iteration count |

## Open questions

None. The orb's artistic redesign (C7) and the other schools' art (C4a) come later.

## Built 2026-11-14

Branch `ui/environment-tokens`. Tests are in `src/lib/rooms.test.ts` and `src/lib/tokens.test.ts`.

- **C1** built. `Dive`, `Glance` and `PortalHub` read the void tokens (new `--glyph-edge` and `--obsidian` for two glyph greys). `c1_no_void_hex_outside_app_css` now scans every `.svelte` file's style and markup, with the pixel-art files as the only exceptions.
- **C3** built. `watchVisible()` in `rooms.ts` sets `data-hidden` on the root while the app is backgrounded, and the pools pause (`c3_ground_pauses_when_backgrounded`).
- **C4** built. `applyRoom` takes the student's school (`setSchool`, fed from the core's portal list in `+page.svelte`) instead of PUP. Contrast is tested for all six portal themes in both rooms (`c4_accent_contrast`, 4.5:1 for the accent on cards).
- **C8, C11** built. `--text-display`, `-title`, `-headline`, `-body`, `-label`, `-caption`, `-numeral` in `app.css`, with the sizes the app already used; every exact match in the components now reads the token. Sizes that sit between the roles (0.824, 0.706, 0.882 rem and a few one-offs) are left as they are, because snapping them changes size. That needs a design call.
- **C17** built. The Study session no longer fires Confetti at 80% or more, and LAR stays idle. Grades (a new grade) is the one remaining use.
- **C20** partly built. `--ease-spring`, `--t-quick`, `--t-move` and `--t-hero` exist, and every literal that equals a token uses it. `c20_no_raw_durations` fails on a token-sized literal in any component, and caps the off-scale literals (0.2 s, 0.3 s, 0.4 s ...) at today's count so it can only fall. Files owned by open PRs still carry token-sized literals: `Landing`, `NoteEditor`, `ClassSheet`, `DueCard`, `WeekGrid`, `Today`, `Schedule`, `You`.
- **C21** built. Under Reduce Motion a press has no scale and darkens instead.
- **C7, C9, C10, C12-C19, C22-C28** were not touched by this change.

**Follow-ups:** the frozen files above (duration tokens, 44 pt targets in `NoteEditor`, `Today`, `Schedule`, `You`, `ClassSheet`); snapping the off-scale durations and sizes; the `cargo test` for C4 (`c4_accent_contrast_on_every_room`) is covered here by the vitest only.

**Status stays "ready to build"**: C20's off-scale literals and C8's between-role sizes are not finished.
