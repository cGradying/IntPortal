# 043 Class changes and calendars UI (basic)

**Status:** draft, wording to confirm

## What changes for the student

The screens for specs 023, 031 and 014 get a plain, working first design: class change buttons in the class sheet, a badge on changed classes, other calendars' events in Day and Week view, a Calendars section on You, LAR's class-change cards, and the first-run setup screen. This is a placeholder design built from existing components; a polish pass comes later.

## Direction and references

- Use what exists: tokens and type from `DESIGN.md`, the class sheet, `WeekGrid.svelte`, the Day list in `Schedule.svelte`, the confirm card in `AssisSheet.svelte`, the rows and switches on `You.svelte`, the first-run layout in `FirstRun.svelte`.
- No new visual system, no new illustrations, no new motion.

## Keep

- Every existing screen's layout and behaviour; the hatched busy spans in Week view stay for calendars shown as busy only.
- Reduce Motion behaviour and touch sizes from `DESIGN.md`.

## Behaviour

**Class sheet**

- **C1.** The class sheet gains a row of four buttons under the time: "Vacant", "Online", "Move", "Cancel". The current mark is shown selected; tapping it again clears it.
- **C2.** Each button asks "This date only" or "For the rest of the term" in a two-option sheet before saving.
- **C3.** "Move" opens a simple form: day (chips Mon to Sat), start and end time (native time inputs), room (text). Save is disabled until the end is after the start.
- **C4.** A changed class shows a small text badge in Day view, Week view and Today: "Vacant", "Online", "Moved", "Cancelled". A moved class shows its new time; its old slot is not drawn.

**Day and Week view**

- **C5.** Events from other calendars draw as blocks in their calendar's colour at 60% opacity with the title, behind or beside classes; classes stay solid and on top.
- **C6.** All-day events sit in one strip at the top of the day column, one line each, "+2" when more than two.
- **C7.** A "+" button in the Schedule header opens "Add event" (spec 031 C7).

**You → Calendar**

- **C8.** Two lists, "Calendars on this phone" (switch rows with colour dot, name, account) and "My calendars" (rows with colour dot and name, a "New calendar" row at the end).
- **C9.** "New calendar" is a small sheet: name field and 8 colour swatches in a row; "Create" at the bottom.

**LAR's cards**

- **C10.** A class-change card uses the existing confirm card: one before-and-after line, a scope line, "Apply" and "Not now"; after Apply it shows the done line and "Undo".
- **C11.** An extra-session card shows subject, date, time and the target calendar with a small calendar picker.

**First-run setup**

- **C12.** The setup step (spec 014) is one screen: two text fields, two chip rows, the live preview line, "Next" as the primary button and "Skip" as a link, matching the other first-run steps.

**You → IntAssis**

- **C13.** "Your study buddy" sits above the style note with the same four fields as C12, saving on change.

## Copy

Strings are owned by specs 023, 031 and 014; this spec only adds the button labels above: "Vacant", "Online", "Move", "Cancel", "This date only", "For the rest of the term", "Add event", "New calendar", "Create".

## Data shape

None of its own; it renders the state from specs 023, 031 and 014.

## Errors

Inline under the field or button that failed, in the error colour, one line.

## Motion and Reduce Motion

Existing sheet and card motion only. No new animation.

## Accessibility

- Buttons at least 44 by 44 points; the change buttons are a group with the current mark announced.
- Badges are text, not colour only.
- Calendar colours are paired with names in screen-reader labels.

## Out of scope

- Visual polish, illustration, custom motion, haptic tuning.
- Drag to create or move.

## Test map

| Criterion | Check |
|---|---|
| C1–C4 | vitest of the class sheet state; screenshot on the UI simulator |
| C5–C7 | screenshot with a seeded calendar on iOS simulator and Android emulator |
| C8–C9, C13 | vitest of the lists; screenshot |
| C10–C11 | vitest of card rendering from a proposal |
| C12 | screenshot of first run |

## Open questions

1. Should "Cancel" be dropped from the class sheet if spec 023 keeps cancel and vacant as one mark?
2. Is 60% opacity enough contrast for other calendars' blocks in the dark theme?
