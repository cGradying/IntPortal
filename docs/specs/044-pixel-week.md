# 044 Pixel week

**Status:** shipped (2026-11-14, release 0.1.9). Picked in round seven of the mockups: Week and Day kept, tap to open a day, and readable details.

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
- Times and faculty names in the reading face, never in Pixelify ([045](045-app-environment.md) C9).

## Behaviour

**Blocks**

- **C1. Stepped blocks.**
  - A class block is a flat fill in its course colour, with pixel-notched corners (one 2 px step) and a 2 px tile gap to its neighbours and the column edge.
  - No rounded corners and no drop shadow.
- **C2. What a block says.**
  - In the even week, a block shows the class title, up to four lines, wrapping on words only. The hour rail gives the time.
  - The app has no room data (`ClassSession` has the code, title, faculty, day and times), so the mockups' rooms were sample text. Where they show a room, the app shows the faculty.
  - In an open day (C13), a block adds the code, and the time and faculty on one line.
  - Text picks ink or white, whichever reads better on the course colour.
  - Times and faculty names are in the reading face (045 C9).
- **C3. Days shown (picked).** Days with classes, plus today, are full columns. Empty days are 7 px hatched ghost columns that keep their place, so a moved class still lands where the student expects it.

**Stamps**

- **C4. Marks are stamps.**
  - Online, vacant and moved classes carry a small stamp as the block's first line: `ONLINE` in the online ink, `VACANT` in the vacant ink, and `MOVED` in the in-person ink with a dashed outline.
  - Vacant blocks also get a 45° hatch. Colour is never the only signal.
- **C5. The stamp thunk.** A stamp that is new since the last visit lands with the `thunk` (0.55 s, eased) plus a 2 px shake of its block, once. Stamps the student has already seen just sit there.
  *Built 2026-11-14:* the block of a new stamp jolts 2 px, once, as the stamp lands (`.jolt`); off under Reduce Motion.
- **C6. Moved shows both places.** A moved class shows on its new day and time. In week view, a dashed ghost of the block stays at the old slot for that week.

**Time**

- **C7. Finished classes lose their colour, not their text.** On today's column, a finished class's fill drops to 42% over the ground, and its text stays at full reading contrast. The class in progress keeps full colour and a 2 px inner edge in the accent.
- **C8. The now-line glides.**
  - The now-line is a 2 px accent line behind the blocks, so it never crosses a class's text, with a time tag (`1:10`) in the reading face on the hour rail.
  - It moves continuously, drawn with a transform each frame at 1 fps or more, so it never jumps a minute at a time.

**Moving between days and weeks**

- **C9. The day view puts details first.**
  - Each class is a card tall enough for all its details: the start and end time on the left, then the course colour as a bar, then the code, title and faculty in full. Its height grows gently with length (58 px, plus 0.2 px for each minute over an hour).
  - Free time of 30 minutes or more folds into a 20 px dashed band labelled `1h 30m free`. If the student is in that gap now, the band is outlined in the accent and reads `Now · free for 40m`.
  - A finished class keeps readable text on a sunken fill. The class in progress has an accent edge, `1h 20m left` beside its faculty, and a 2 px progress bar along its bottom.
  - A moved class leaves one dashed row at its old place: `4:00 · Object-Oriented Prog. moved to Thu 3:00`.
  - The day fits one screen in the normal case, and otherwise it scrolls.
- **C9a. Day swipe.**
  - In day view, a horizontal drag moves the list with the finger. Past 60 px or a quick flick, it springs to the next or previous day, using the spring in `carousel.ts`. Otherwise it springs back.
  - The day strip's selection slides with it.
  *Built 2026-11-14:* the day list and the day strip's gold selection follow the finger and settle on the spring from `carousel.ts` (a frame loop in `Schedule.svelte`).
- **C10. Week swipe.** In week view, a horizontal swipe changes the week with the same spring, and the header names the week (`This week`, `Next week`, or the date range).
  *Built 2026-11-14:* a change of week, by swipe or the arrows, slides in on the same spring; the header reads `This week · Oct 27 – Nov 2` (`weekRange`). An empty week shows LAR with "No classes this week. Pahinga muna." above the grid, which keeps the hatched own events. Vitest `c2_block_lines`, `c13_open_day_and_let_go`, `c10_week_range`.
- **C11. The four-week month (picked).** Beside the screen title sits a 7 × 4 pixel month: one 5 px square per day for the next four weeks, gold when something is due, red when overdue, with today outlined and the current week lighter. Each day header in the week also carries a 4 px pin when something is due that day.
- **C13. Open a day.**
  - Tapping a day's column or header in week view opens it: its column eases to 5.5 times the others' width over 0.36 s, and its blocks add the code, the time, larger text and the free gaps. The other days keep their blocks as colour only, with a white pixel where a block has a stamp.
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

See C5, C8–C10 and C12. The spring is the existing one from `carousel.ts`. Stamps use 0.55 s, eased. Nothing loops.

## Accessibility

- Each block's label reads the code, title, time, faculty and mark (`COMP 20073, Data Structures, 7:30AM to 9AM, SANTOS, JUAN, online`).
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
| C2 | `vitest`: `c2_block_lines` (even week and open day), `c2_text_colour_contrast` on every course colour |
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
