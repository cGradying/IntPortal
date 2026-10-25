# 043 App environment

**Status:** draft. Criteria marked **(pick)** wait for the Step 3 mockups.

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
- **C2. (pick) The Night room** takes one of the following:
  - (a) the void family as its ground;
  - (b) the charcoal it has today, with the void kept only for stages;
  - (c) charcoal tinted toward the void.
- **C3. (pick) The backdrop:**
  - the dot grid as today;
  - a slow drifting gradient in the school's ramp, as on LAR's stage;
  - none.
  Whatever moves stops under Reduce Motion.
- **C4. (pick) Each school's colours.** The accent and stage gradients come from the active portal's theme (`crates/intportal-core/src/schools.rs`), not fixed gold. Contrast stays at 4.5:1 or better, checked by test for every school.
- **C5. Corner roles.**
  - The pixel notch (stepped 4 px corners) is for stages and hero cards: Up next, the GPA card, sheets.
  - Dense rows and week blocks get a 4 px square-ish radius.
  - Nothing else.
- **C6. Form controls** take the room's accent (`accent-color`), never system blue. **(pick)** Pixel checkboxes and switches instead.
- **C7. The orb's lane.**
  - The cube orb never rests on top of a tappable control or a grade stamp.
  - **(pick)** The lane is one of: a notch in the tab bar's right end, hide while scrolling down, or a slot in the screen header.

**Type**

- **C8. Roles.** There are seven text roles, and every text style in the app maps to one of them:
  - `display`
  - `title`
  - `headline`
  - `body`
  - `label`
  - `caption`
  - `numeral`

  **(pick)** Their faces come from one of these directions:
  - (a) system UI for reading, with Pixelify for play;
  - (b) Geist with Pixelify;
  - (c) Instrument Serif for titles only, with system UI for reading.

  Montserrat and Source Sans are removed if they are not picked.
- **C9. The pixel rule.** Pixelify sets play only: LAR's name and bubbles, stamps, chips, section tags and celebrations. It never sets a time, a room, a date or a due item.
- **C10. Pixel numerals.** A hand-drawn numeral set (0–9, `:`, `.`, `%` and small-caps `AM`/`PM`), drawn as SVG sprites in the way `PixelIcon` is. The numerals are tabular, and their sizes snap to the art pixel. **(pick)** Use them for hero numbers only (the Up next time, GPA, Study counts) or for every number.
- **C11. Scale.** Seven sizes, one per role, each with a `rem` value and a cap. Each cap is above the caps of the roles under it, so a title never equals body at the largest text size. The 17 sizes in use today collapse into these seven. **(pick)** The values come from the mockup.
- **C12. Units.** A number and its unit always have a gap or a size change between them, so `0 days`, never `0days`.

**Juice**

- **C13. Press.**
  - Every tappable card and button squashes to 0.97 on press and springs back with a slight overshoot. **(pick)** The level is subtle, medium or loud.
  - The data inside a card never moves on its own.
- **C14. Count-up.** Hero numbers (GPA, the Study counts, units done) count up from their last seen value when the screen opens. They do not count up from zero on every visit.
- **C15. Stamps thunk.** Stamps land with the existing `thunk` (0.55 s, `steps(6)`) plus a 2 px shake of the card they land on, once per new grade or status.
- **C16. (pick) Idle sway.** Decorative pieces may sway (LAR, the cube, stamps, scene props). Cards and data never do.
- **C17. Celebrations.** One kit: tile confetti, LAR's hop and a cube sparkle. It fires only on these three:
  - the first sign-in (the dive's reveal);
  - a deadline marked done;
  - a new grade posting.

  Nothing else celebrates.
- **C18. Play limits.**
  - No streak guilt, no loss framing, no hidden suspense and no random rewards.
  - Repeated actions get smaller feedback: the second "done" within 10 s gets only the press.
- **C19. Sound.**
  - A tiny pixel sound kit (press tick, stamp, done, celebrate, LAR blip), under 40 KB in all.
  - A switch in You turns it on. It is off by default.
  - It respects the silent switch, and plays nothing under Reduce Motion with "Play animated effects" off.

**Motion tokens**

- **C20.** Motion goes through tokens in `app.css`:
  - `--ease` (standard);
  - `--ease-spring` (overshoot);
  - `--t-quick` 0.16 s;
  - `--t-move` 0.32 s;
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
| C18 | `vitest`: `c18_second_done_within_10s_is_quiet` |
| C19 | `vitest`: off by default; muted under Reduce Motion |
| C20 | `vitest`: `c20_no_raw_durations` (scan for `s` literals outside tokens and `steps()`) |
| C21 | `vitest` on the CSS: the reduce rule sets the iteration count |

## Open questions

The Step 3 mockups resolve all of these:
- C2 (Night room)
- C3 (backdrop)
- C4 (school colours across the app)
- C6 (pixel controls)
- C7 (orb lane)
- C8 (type direction)
- C10 (numeral reach)
- C11 (scale values)
- C13 (juice level)
- C16 (sway)
