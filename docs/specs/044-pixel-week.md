# 044 Pixel week

**Status:** draft. Criteria marked **(pick)** wait for the Step 3 mockups.

## What changes for the student

The week and day views look like IntPortal's own calendar, not a generic one. Classes are stepped pixel blocks with tile gaps. Online, vacant and moved classes carry stamps that thunk on. Finished classes fade, and the now-line glides. Swiping between days moves the grid with a spring instead of jumping.

## Direction and references

- [Reference sheet](reference/prototypes/reference-sheet.html). It supplies the stamp inks (in person `#7a1128`, online `#1b4f99`, vacant `#765806`), stamps rotated about −0.1 rad and set in Pixelify with an ink mask, and the notch.
- [Critique 2026-10-25](reference/critique-2026-10-25.md), finding 6.
- [Market scan](reference/market-scan-2026-10-25.md), takeaways 3 and 10: grey out finished classes; mark moved and cancelled classes with a label plus a pattern, not colour alone.
- Today's code: `src/lib/WeekGrid.svelte` and `src/lib/screens/Schedule.svelte`.

## Keep

- The Day/Week switch, the day strip and "Hide vacant classes".
- Tapping a block opens the class sheet (`ClassSheet.svelte`).
- Course colours from `subjectColor`. The student's own events show hatched behind the classes.
- Times and rooms in the reading face, never in Pixelify ([043](043-app-environment.md) C9).

## Behaviour

**Blocks**

- **C1. Stepped blocks.**
  - A class block is a flat fill in its course colour, with pixel-notched corners (one 2 px step) and a 2 px tile gap to its neighbours and the column edge.
  - No rounded corners and no drop shadow.
- **C2. What a block says.**
  - Every block shows the course code on one line, never split.
  - When the block is at least 44 px tall it adds the title, and at 66 px or taller it also adds the room.
  - Text truncates with an ellipsis, never mid-word wrap.
- **C3. (pick) Days shown.** One of:
  - (a) Mon–Sat always, plus Sun when it has a class or is today;
  - (b) days with classes only, as today, with empty days as thin ghost columns that keep their place.

  Recommendation: (a). The week then reads as a week, and a moved class lands where the student expects it.

**Stamps**

- **C4. Marks are stamps.**
  - Online, vacant and moved classes carry a small stamp in the block's top-right corner: `ONLINE` in the online ink, `VACANT` in the vacant ink, and `MOVED` in the in-person ink with a dashed outline.
  - Vacant blocks also get a 45° hatch. Colour is never the only signal.
- **C5. The stamp thunk.** A stamp that is new since the last visit lands with the `thunk` (0.55 s, `steps(6)`) plus a 2 px shake of its block, once. Stamps the student has already seen just sit there.
- **C6. Moved shows both places.** A moved class shows on its new day and time. In week view, a dashed ghost of the block stays at the old slot for that week.

**Time**

- **C7. Finished classes fade.** On today's column, classes that have ended drop to 45% opacity. The class in progress keeps full colour and a 2 px inner edge in the accent.
- **C8. The now-line glides.**
  - The now-line is a 2 px accent line with a 6 × 6 pixel nub at the hour rail.
  - It moves continuously, drawn with a transform each frame at 1 fps or more, so it never jumps a minute at a time.
  - It sits above the blocks and below the stamps.

**Moving between days and weeks**

- **C9. Day swipe.**
  - In day view, a horizontal drag moves the list with the finger. Past 60 px or a quick flick, it springs to the next or previous day, using the spring in `carousel.ts`. Otherwise it springs back.
  - The day strip's selection slides with it.
- **C10. Week swipe.** In week view, a horizontal swipe changes the week with the same spring, and the header names the week (`This week`, `Next week`, or the date range).
- **C11. (pick) Month strip.** One variant adds a deadline strip above the week: a row of 28 dots, one per day, filled on days with something due. Tapping a dot jumps there. The mockup decides whether it ships.

**Reduce Motion**

- **C12.**
  - No thunk, no shake, no spring: stamps appear in place, swipes cut, and the now-line updates every minute without gliding.
  - The global Reduce Motion rule also sets `animation-iteration-count: 1` ([043](043-app-environment.md) C21).

## Copy

- Stamps: `ONLINE`, `VACANT`, `MOVED`.
- Week header: `This week`, `Next week`, `Last week`, otherwise `Oct 27 – Nov 2`.

## Data shape

- `Meeting.mark` (`in_person | online | vacant`) and `Meeting.moved`, already in `api.ts`.
- C6 needs the old slot. Moves are stored as `marks.moved` (`Layers<Slot>`, keyed by session id), and the term's original session is in `snapshot.schedule`, so the old slot can be derived without a new field. Confirm this before building.
- The seen-stamps set lives in `localStorage` under `intportal.week.seen`, inside `try`/`catch`.

## Errors

- If there are no classes this week, the view shows LAR with `No classes this week. Pahinga muna.` and the hatched own events stay visible.

## Motion and Reduce Motion

See C5, C8–C10 and C12. The spring is the existing one from `carousel.ts`. Stamps use 0.55 s `steps(6)`. Nothing loops.

## Accessibility

- Each block's label reads the code, title, time, room and mark (`COMP 20073, Data Structures, 7:30 to 9 AM, room S501, online`).
- The stamps are part of the block's label, not separate elements.
- Swipes also have buttons: previous and next day or week, 44 pt each.
- Block text keeps 4.5:1 contrast on every course colour in every room.

## Out of scope

- Editing or creating classes.
- A month view.
- The Today list ([043](043-app-environment.md)).

## Test map

| Criterion | Check |
|---|---|
| C1 | screenshot in both rooms |
| C2 | `vitest`: `c2_block_lines_by_height` (44 px and 66 px thresholds) |
| C3 | `vitest`: `c3_days_shown` |
| C4 | `vitest`: `c4_stamp_per_mark`, plus the hatch on vacant |
| C5 | `vitest`: `c5_thunk_once_per_new_stamp` |
| C6 | `vitest`: `c6_moved_ghost_at_old_slot` |
| C7 | `vitest`: `c7_finished_classes_fade` at a fixed clock |
| C8 | recording: the line moves smoothly over 2 minutes |
| C9, C10 | recording; `vitest`: threshold and flick velocity |
| C11 | screenshot, if picked |
| C12 | `vitest` on the CSS rule; recording with Reduce Motion on |

## Open questions

- C3 (days shown)
- C11 (month strip)
