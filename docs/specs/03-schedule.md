# 03 — Schedule

Status: approved design (prototypes v1 + v2). Answers vault task T-007 ("too plain and empty").

## Reference
Prototype `intportal-v2.html`: `#s-schedule`, `renderGrid()`, `renderCor()`, `select()`, stamps.

## Current behaviour inventory (must keep)
From `Views/CalendarView.swift`, `WeekGrid.swift`, `Blocks.swift`, `GridInteractionLayer.swift`,
`YearView.swift`, `ScheduleSidebar.swift`, `SelectionBar.swift`, `EventEditorPopover.swift`,
`WeekPrintView.swift`:
- Week grid with dated headers, scroll-to-now on open, overlap lanes, now-line.
- Drag to create (multi-day, 15-min snap, chip "New Event(s)"), right-click "New Event at 3:00 PM".
- Move / resize with "This event repeats." → This Event Only / All Future Events / Cancel; undo with
  named actions.
- Multi-select (⌘-drag band, Shift/⌘-click, ⌘A events only), SelectionBar "N selected" Delete ⌫ /
  Duplicate ⌘D / Done Esc.
- Event menu Edit… / Duplicate / Colour / Delete; EventEditorPopover (title, repeat weekly/just
  this week, calendar, description, link, delete, duplicate, save).
- Class block: Status In Person / Online / Vacant, this week vs "Every week this term", online
  link + Join, description, "Apply to every CODE block", start/end override with "SIS: <time>" +
  Reset, colour swatches + custom + Reset.
- Year view (click a day → that week), show/hide cancelled, Print (week range, PDF menu),
  Refresh / Try again, "Updated N min ago", next-class banner, syllabus/tasks/files in the sidebar,
  update badge, empty and error states.

## UX changes
1. **Island controls** (spec 12): ‹ range › · Today · **Week | COR | Year** · Show cancelled ·
   New event · Refresh, built as a standalone `ScheduleControls` view that the island hosts.
2. **COR strip** above the grid: School year · Semester · Units · Updated {time} from {host}.
3. **COR view**: the week as the Certificate of Registration table (Subject, Description, Schedule,
   Room, Units, This week stamp), total units footer. Lab/Lec rows count units once.
4. **Class inspector panel** (290pt, slides in right) replaces the class popover: code + title,
   When / Room / Units, **Stamp this week** (three stamp buttons, the chosen one thunks onto the
   block), "Every week this term", online link, time override, colour. Events keep
   `EventEditorPopover`, restyled.
5. **Blocks**: notch, subject tint, code in display, time in display 12, title if tall, stamp
   bottom-right; vacant = hatch; selected = 2pt inset subject ring.
6. **Today column** gold wash; **now-line** 2pt gold with a gold time chip in the gutter.
7. **Right sidebar content** (next class, syllabus tasks, files & links) moves: next class → Today;
   syllabus → Syllabus screen; files & links → class inspector. Print moves to the toolbar ⋯ menu.

## States
Signing in / refresh failed / no classes found / stale cache — same copy as today, shown as a sheet
empty state with dither.

## Accessibility & motion
Blocks announce "GEED 020, Wednesday 6 to 9 PM, in person". Stamp buttons are a radio group.
Reduce Motion: no thunk, no inspector slide.

## 3D
Paging weeks plays `WeekTurn` (token `turn`): left into the past, right into the future. The variant (cube or slab) comes from prototype v3.

## Acceptance criteria
- [ ] ⌘[ / ⌘] and the week arrows turn the grid in the direction of time; a key pressed mid-turn redirects it. Evidence: screenshots mid-turn.
- [ ] Every inventory item works (drag, resize, undo, multi-select, repeat scope, print, year view).
      Evidence: manual pass; `GridGeometryTests`, `TimeSnapTests`, `EventEditor` tests.
- [ ] Status stamping updates grid, COR, Today and notifications. Evidence: manual + Notifier test.
- [ ] Matches the prototype at 1280×820 light/dark. Evidence: screenshot pairs.

## Seams
`CalendarBridge`, `EventEditor`, `Preferences.status/color/termTime`, `Notifier`. Backend fixes W4
(undo) and W5 (export/reminder keys) should land first.
