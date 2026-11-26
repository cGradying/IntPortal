# 064 LAR changes the calendar

**Status:** draft

## What changes for the student

The student can tell LAR to change their week. LAR handles:
- **Deadlines:** "add a lab report due Friday", "move my lab report to Monday", "I finished the essay".
- **Classes:** "no MATH class tomorrow", "Friday's COMP class is online", "move my review class to 3 pm every week".
- **Reminders:** "delete the tuition reminder".

LAR shows a card with what will change, and nothing changes until the student taps. Undo puts it back. The change shows in Today, Schedule and the phone's IntPortal calendar right away. School data from the SIS and eMabini is never rewritten.

## Direction and references

- The owner, 2026-11-27: "make changes to the calendar". The owner took every recommended answer ("sure with all"):
  - LAR changes the student's own deadlines, their own classes, and its own reminders.
  - School data stays read-only. A school deadline can only be marked done.
  - A class change is for one meeting by default. It changes every week only with "every week" or "from now on".
  - Changes reach the phone's calendar through the sync the app already has.
  - Each change gets a card first, and one Undo step.
  - It costs no model call. The rules read the request, and a picker shows when the match is unclear.
  - LAR can delete reminders it made.
- ADR 0003 and spec 062's confirm-first pattern hold. The cards look like 062's, as picked in round 1 (063 C4–C6).
- What exists today:
  - Own deadlines: `OwnDeadline`, through `save_own` and `delete_own` (041). Any deadline can be marked done with `set_done`.
  - Own classes: `OwnClass`, through `save_class` and `delete_class` (061).
  - One-week or whole-term class marks (in person, online, no class) and moves: `Marks { mode, moved }`, as `Layers` (term, or keyed by week).
  - The phone calendar export: `class_events` and `deadline_events` (041 C21–C24).

## Keep

- Every way of changing these by hand: the deadline sheet, the class editor, and the marks and moves on Schedule.
- The sync rule that a sync never removes the student's own items (061).
- The evening-before reminders (041) and the reminders LAR sets (021).
- 062's request order. Calendar changes slot in after note edits (C1).

## Behaviour

### Which request it is

- **C1. Order.** Note edits keep their place (062 C0). The new order is: note edit > calendar change > remind > cards or quiz > note > Due, Classes, Grades > open question.
- **C2. A calendar change needs a verb and a thing.**
  - The verbs are add, move, change, cancel, delete, remove, "no class", "is online", finished, done, tapos, "wala", and ilipat.
  - The things are a deadline (deadline, due, assignment, quiz, exam, lab, essay, project, report), a class (class, klase, or a subject code or name the student has), or a reminder.
  - "When is my lab due?" is still a Due question. A question word at the start never makes a change (as 062's edit rule).

### Deadlines

- **C3. Add.** "Add a lab report due Friday" makes a card for a new own deadline.
  - It carries the title, the subject if one is named, the kind read from the words, and the date, read by the rules (`resolve_when`).
  - With no date, it says "When is it due?" and makes no card.
- **C4. Move or rename.** "Move my lab report to Monday" and "rename the essay to Reflection paper" work only on the student's own deadlines. For a school deadline, LAR says "That deadline comes from {source}, so I can't move it. I can mark it done."
- **C5. Done.** "I finished the lab report" or "tapos na ako sa essay" marks any deadline done, own or school, through `set_done`.
- **C6. Delete.** "Delete the lab report" deletes an own deadline, with a red Delete button. School deadlines can't be deleted.

### Classes

- **C7. One meeting, by default.** "No MATH class tomorrow", "Friday's COMP is online", and "move tomorrow's COMP to 3 pm" change that one week's meeting. They go through the same `Marks` (mode or moved) as Schedule's own buttons. They work for every class, from the school or the student's own, because marks are the student's and the SIS never sees them.
- **C8. Every week, when said.** "Every week", "from now on", or "lagi" makes the same change for the whole term.
- **C9. Own class details.** "Change my review class room to 302" or "rename my org meeting" edits an own class through `save_class`. A school class's room and name stay as the SIS has them. LAR says "Your school sets that class's room. I can mark a day online or no class, or move one meeting."
- **C10. Add or delete a class.** "Add a class" opens the existing class editor, filled with what the rules read. LAR doesn't add a class straight from chat, because a class has too many fields to confirm on one card. "Delete my org meeting class" deletes an own class, with a red Delete button.

### Reminders

- **C11. Delete or move LAR's own reminders.** "Delete the tuition reminder" and "move the tuition reminder to Saturday" work on the reminders LAR set (021). LAR finds them by their text, so each one is now stored with its text, not only its id and time. The evening-before reminders (041) aren't LAR's: they follow the deadline they belong to.

### Which one

- **C12. Matching.** Deadlines match on their title and subject, classes on their code, name and day, and reminders on their text, scored as 062 C8. With one clear match, that one is used. With two to four, LAR shows note rows (063 C6) for deadlines, classes or reminders. With none, it says "I couldn't find that in your week."
- **C13. Dates are read by the rules.** "Tomorrow", "Friday", "next Monday", "bukas", "sa Biyernes", "Dec 3" and "3 pm" are all read without the model. A day in the past is refused: "That day has passed."

### Confirm, apply, Undo

- **C14. The card.** It uses 063's picked looks. A move or rename shows old over new (063 C4). Done shows the deadline with a check. Delete shows the item's name and the red button. A one-week class change says which week ("Fri, Dec 5 only"), and a whole-term change says "Every week".
- **C15. Apply.** Nothing changes before the tap. After it, Today, Schedule and the deadline list show the change, and the phone's IntPortal calendar is rewritten by the existing sync. The card stays dimmed with "Changed · Undo" (063 C5).
- **C16. Undo.** It puts back exactly what was there before:
  - the old deadline, class or mark;
  - a deleted own item;
  - a reminder, rescheduled.
  It holds one step per change. A later change to the same item by hand ends that Undo, as with notes (062 C14).

### Cost

- **C17. No model call.** Every calendar change is read and applied by rules. Like a note edit's picker, the "Which one?" picker is rules too. The model is never woken for these.

## Copy

| Where | Text |
|---|---|
| No date | When is it due? |
| School deadline, move or delete | That deadline comes from {source}, so I can't move it. I can mark it done. |
| School class detail | Your school sets that class's room. I can mark a day online or no class, or move one meeting. |
| Nothing found | I couldn't find that in your week. |
| A past day | That day has passed. |
| Card label, deadline | New deadline / Move deadline / Rename deadline / Mark done / Delete deadline |
| Card label, class | No class / Online / Move class / Change class / Delete class |
| Card label, reminder | Move reminder / Delete reminder |
| One week | {Day}, {Mon} {d} only |
| Whole term | Every week |
| After Apply | Changed · Undo / Deleted · Undo / Done · Undo |
| After Undo | Put back |

## Data shape

- Each LAR reminder is stored with its text: `{ id, at, text }`, under `larReminders` in `src/lib/assis/apply.ts`. Older entries without text can't be matched by C11, and expire with their time.
- New proposals in `crates/intportal-ai/src/assis.rs`:
  - `AddDeadline { title, subject, kind, date }`
  - `ChangeDeadline { id, title, date }`
  - `DoneDeadline { id }`
  - `DeleteDeadline { id }`
  - `MarkClass { session, week: Option<Date>, mark }`
  - `MoveClass { session, week: Option<Date>, slot }`
  - `ChangeOwnClass { was, class }`
  - `DeleteOwnClass { code }`
  - `MoveReminder { id, at }`
  - `DeleteReminder { id }`
  - `PickItem { candidates, ask }`
- The facts LAR gets (`Facts`) gain the student's deadlines (with source), classes, and LAR reminders, as compact rows for matching. Rows only, not prompt text, since no model call reads them.
- Undo: the shell keeps the item as it was before each applied change, in memory and in the chat message, the way notes keep `note_undo`. Calendar items are small, so it is held in the message state and restored through the same commands.

## Errors

- Apply fails (store or sync error): the card stays live, with "Couldn't save that. Try again." The sync's own errors show as they do today.
- The item changed by hand between the card and the tap: "That changed since I read it. Ask me again."
- Notifications are off when moving a reminder: the move is saved, with the same note 021 shows today.

## Motion and Reduce Motion

As 063: the chat's card entrance, and the dim after Apply. No new motion.

## Accessibility

- As 062 and 063.
- A one-week or whole-term change is read out: "Friday, December 5 only" or "Every week".
- Picker rows say what kind of item each row is: "Deadline", "Class" or "Reminder".

## Out of scope

- Changing what the SIS or eMabini says: their deadlines, rooms, times and names.
- Any calendar on the phone other than IntPortal's own.
- Recurring deadlines.
- Adding a whole class from one chat message (C10 opens the editor instead).
- Undo deeper than one step.

## Build order

1. `ai/calendar-rules` (AI role): C1, C2, C12, C13 and C17. This covers the intent, the matching, and the dates, with table tests in English, Taglish and Filipino.
2. `ai/calendar-changes` (AI role, with core for the commands): C3–C11 and C14–C16, the proposals, apply and Undo.
3. The UI role checks the cards against 063's look on the simulator, Night and Day.

## Test map

| Criterion | Check |
|---|---|
| C1, C2 | `cargo test -p intportal-ai intent`: change requests vs Due questions, question words, Taglish |
| C3–C6 | `assis` tests with facts: each deadline proposal, the school-deadline refusals, a missing date |
| C7–C10 | `assis` tests: one week vs every week, own vs school class, the class editor handoff |
| C11 | vitest: a LAR reminder found by its text, moved and deleted; an old entry without text isn't matched |
| C12, C13 | `assis` tests: one match, a picker of 2–4, none; dates from the tables; a past day refused |
| C14–C16 | vitest on apply and Undo for each proposal; a simulator run that checks Today, Schedule and the phone calendar after Apply and Undo |
| C17 | stub-model tests: no calendar change makes a model call |

## Open questions

None. The owner took every recommended answer on 2026-11-27.
