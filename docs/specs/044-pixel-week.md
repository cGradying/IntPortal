# 044 Pixel week

**Status:** draft. The layout was picked in round four of the mockups (B, Week and Day kept), with tap-to-open from round five.

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
- Events from the phone calendars a student connects ([031](031-calendar-connections.md), in review in #191) use the same hatched treatment, so classes stay the solid blocks.
- Times and rooms in the reading face, never in Pixelify ([045](045-app-environment.md) C9).

## Behaviour

**Blocks**

- **C1. Stepped blocks.**
  - A class block is a flat fill in its course colour, with pixel-notched corners (one 2 px step) and a 2 px tile gap to its neighbours and the column edge.
  - No rounded corners and no drop shadow.
- **C2. What a block says.**
  - A block leads with the class title, wrapping on words only, up to three lines. Under it come the time and, pinned to the bottom, the room, both in the label face.
  - The course code shows only in an opened day (C13) and in the class sheet.
  - Text never breaks mid-word, and it clips rather than showing an ellipsis.
- **C3. Days shown (picked).** Days with classes, plus today, are full columns. Empty days are 7 px hatched ghost columns that keep their place, so a moved class still lands where the student expects it.

**Stamps**

- **C4. Marks are stamps.**
  - Online, vacant and moved classes carry a small stamp as the block's first line: `ONLINE` in the online ink, `VACANT` in the vacant ink, and `MOVED` in the in-person ink with a dashed outline.
  - Vacant blocks also get a 45° hatch. Colour is never the only signal.
- **C5. The stamp thunk.** A stamp that is new since the last visit lands with the `thunk` (0.55 s, `steps(6)`) plus a 2 px shake of its block, once. Stamps the student has already seen just sit there.
- **C6. Moved shows both places.** A moved class shows on its new day and time. In week view, a dashed ghost of the block stays at the old slot for that week.

**Time**

- **C7. Finished classes fade.** On today's column, classes that have ended drop to 45% opacity. The class in progress keeps full colour and a 2 px inner edge in the accent.
- **C8. The now-line glides.**
  - The now-line is a 2 px accent line with a time tag (`1:10`) on the hour rail.
  - It moves continuously, drawn with a transform each frame at 1 fps or more, so it never jumps a minute at a time.
  - It sits above the blocks and below the stamps.

**Moving between days and weeks**

- **C9. The day view is a timeline.** Classes sit on the hour rail at their real length, as cards with the course colour as a bar, and the free gaps of 45 minutes or more between them are dashed bands labelled `1h 30m free`. A moved class leaves a dashed `Moved to Thu 3:00` card at its old slot.
- **C9a. Day swipe.**
  - In day view, a horizontal drag moves the timeline with the finger. Past 60 px or a quick flick, it springs to the next or previous day, using the spring in `carousel.ts`. Otherwise it springs back.
  - The day strip's selection slides with it.
- **C10. Week swipe.** In week view, a horizontal swipe changes the week with the same spring, and the header names the week (`This week`, `Next week`, or the date range).
- **C11. The four-week month (picked).** Beside the screen title sits a 7 × 4 pixel month: one 5 px square per day for the next four weeks, gold when something is due, red when overdue, with today outlined and the current week lighter. Each day header in the week also carries a 4 px pin when something is due that day.
- **C13. Open a day.**
  - Tapping a day's column or header in week view opens it: its column eases to four times the others' width over 0.36 s, and its blocks add the course code, larger text and the free gaps. The other days keep their blocks as colour only, with a white pixel where a block has a stamp.
  - Tapping the open day again, any drag of more than 10 px on the grid, a scroll, or a week swipe closes it, and the week goes back to even.
  - With a day open, tapping one of its classes opens the class sheet. With no day open, tapping a class opens its day.
  - Reduce Motion: the widths change without easing.

**Reduce Motion**

- **C12.**
  - No thunk, no shake, no spring: stamps appear in place, swipes cut, and the now-line updates every minute without gliding.
  - The global Reduce Motion rule also sets `animation-iteration-count: 1` ([045](045-app-environment.md) C21).

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
- The Today list ([045](045-app-environment.md)).

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
| C11 | screenshot in both rooms |
| C13 | `vitest`: `c13_open_day_and_let_go` (tap opens, a second tap or a 10 px drag closes) |
| C12 | `vitest` on the CSS rule; recording with Reduce Motion on |

## Open questions

- C13: should tapping a class in the even week open the sheet directly, skipping the open-day step? The mockup opens the day first.
