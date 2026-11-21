# 061 Own schedule: classes without a portal

**Status:** building

## What changes for the student

A student whose school has no portal in IntPortal can still use the app. They pick **Own schedule** on the portal wall, type their school's name, and add their classes, either by hand or from a photo of their schedule that the phone reads and they check. A PUP student can add a class the SIS doesn't show, such as a review class or an org meeting, and a sync never removes it.

## Direction and references

The owner, 2026-11-21: "even they don't have a portal for their school they can use it by manually adding schedule name of their classes or even taking a picture and it does an automatic setup". The answers to the grilling round, all taken as recommended: both groups get it; two doors (the wall and the intro's "Another school"); one local data file; the photo is read on the phone and by IntAssis when it is installed, never by a cloud service; list-shaped schedules first; Grades hidden; the names below.

ADR 0002 (data stays on the device) and ADR 0005 (portals are first class) hold. Own schedule is one more entry in the portal registry, with no login.

## Keep

- SIS and eMabini sign-in, sync and their data files, unchanged.
- Marks, subject colours, class notes, deadlines, Study and LAR work on own classes exactly as on synced ones.
- The demo account and the browser demo.
- The camera plugin's one-photo flow, its errors and its "nothing kept unless `saveTo`" rule (041 C16).

## Behaviour

### Own classes

- **C1. Kept apart from a sync.** A class the student adds carries `own: true`. A sync replaces only the classes without it. Signing out of the SIS drops the synced classes and keeps the own ones.
- **C2. What a class is.** A name, one or more meetings (each a set of days with a start and an end time), and optionally a code, a room and a teacher. With no code, the app makes one from the name: the first letters of its words plus any number in it, upper case ("Calculus 1" becomes "C1", "Purposive Communication" becomes "PC"). If that code is taken it gets "-2", "-3".
- **C3. Checks.** Saving refuses a class with no name, no meeting, a meeting with no day, or an end at or before the start, and says which. A meeting at the same day and times as a class already on the week, under the same code, is refused: "That class is already on your week."
- **C4. One class, many sessions.** On the week, an own class is one session per day per meeting, the same shape as a synced class. Editing it replaces all of its sessions; renaming its code moves its colour to the new code.
- **C5. Where they are added.** The Schedule tab's head has "+ Class", which opens the class editor, and "Scan", which opens the photo flow (C10). An own class in its class sheet shows "Edit" and "Remove"; a synced class doesn't.
- **C6. In backups.** A backup carries own classes under `own_classes`; restoring puts them back in place of the own classes on the phone.

### Own schedule mode

- **C7. The door.** The portal registry lists Own schedule last, ready, with one field: the school's name (1 to 60 characters after trimming). Its card on the landing says "For schools without a portal yet. Your classes stay on this phone." with the field and a gold "Start". Start opens the own schedule's data file (one per phone) and lands on the hub, like a sign-in. In the intro, "Another school" leads to the wall as before (049 C6), where Own schedule is one of the choices.
- **C8. Signed in, without a portal.** In own schedule mode the app counts as signed in: Today, Schedule, Study and LAR work. Nothing syncs, and Pull to sync is off. The Grades tab is hidden. Today with no classes shows "Add your classes" with "Add by hand" and "Scan a schedule".
- **C9. Leaving.** You shows "Own schedule · {school}" with "Leave own schedule". Leaving keeps the file; choosing Own schedule again, with any school name, opens it as it was. Signing in to the SIS or eMabini opens that student's own file, as today; the own schedule file stays on the phone.

### From a photo

- **C10. Taking it.** Scan offers Camera and Photos (the existing camera plugin, `read.text`). The phone reads the text and where each line sits. Nothing leaves the phone and the photo is not kept.
- **C11. Reading it.** Lines are joined into rows left to right, each line joining the row whose last line sits nearest its height (within 0.6 of a line), so a tilted photo keeps its rows. A row that has a day and a time range is a class; a row without one that sits right under a class with no name, or whose name is cut short, adds to its name. Days read: M, T, W, Th (or TH, R), F, S (or Sa), Su, joined (MWF, TTh) or separated (M/W, Mon, Tue, Wed, Thu, Fri, Sat, Sun, Lunes to Linggo). Times read: `7:30AM-9:00AM`, `7:30-9:00 AM`, `7:30 - 9:00am`, `13:00-14:30`, `1PM-4PM`, with an end before a lone-AM start read as PM ("10:00-1:00" is 10 AM to 1 PM). A code reads as 2 to 6 letters and 2 to 5 digits, with an optional letter after (COMP 20073, IT101, MATH 1A); a row's first cell of letters and 1 to 4 digits (PE 2, NSTP 1) is its code when a name follows. Rows with the same code and name become one class with several meetings.
- **C12. IntAssis when it reads nothing.** If the rules find no class and IntAssis's model is installed, the model rewrites the text into one line per meeting (`code | name | days | start-end | room`), and the same rules read that. A missing, busy or slow model (40 s) gives "Couldn't find classes in that photo." with "Add by hand".
- **C13. Checking it.** Every found class shows on a review list: its name, code, days and times, each with Edit (the class editor) and Remove. A row the rules were unsure of (no code, or a name under 3 letters) is marked "Check this". "Add {n} classes" saves them all; nothing is saved before it.
- **C14. Typed or pasted text.** The same review takes pasted text ("Paste instead"), read by the same rules without positions.

## Copy

| Where | Text |
|---|---|
| Wall card, title | Own schedule |
| Wall card, line | For schools without a portal yet. Your classes stay on this phone. |
| Wall card, field | Your school |
| Wall card, action | Start |
| Field error | Type your school's name. |
| Hub hint | Own schedule · {school} |
| Today empty | Add your classes · Add by hand · Scan a schedule |
| Schedule head | + Class · Scan |
| Editor title | New class · Edit class |
| Editor fields | Name · Code (optional) · Room (optional) · Teacher (optional) · Days · Starts · Ends · + Another time · Save · Remove class |
| Editor errors | Give the class a name. · Pick at least one day. · It has to end after it starts. · That class is already on your week. |
| Scan sheet | Scan a schedule · Camera · Photos · Paste instead |
| Reading | Reading your schedule… · IntAssis is reading it… |
| Review | Found {n} classes · Check this · Edit · Remove · Add {n} classes · Add 1 class |
| Nothing found | Couldn't find classes in that photo. · Add by hand · Try another photo |
| You | Own schedule · {school} · Leave own schedule |

## Data shape

- `crates/intportal-core/src/model.rs`: `ClassSession` gains `own: bool` and `room: String`, both `serde(default)` and skipped when empty, so stored and synced JSON is unchanged.
- `crates/intportal-core/src/own_class.rs`: `OwnClass { code, name, room, teacher, meetings: Vec<Meeting> }`, `Meeting { days: Vec<Weekday>, start: u16, end: u16 }`; `check`, `sessions_of`, `classes_of` (sessions back into classes), `make_code`, `save` and `remove` on a `Snapshot`.
- `crates/intportal-core/src/timetable.rs`: `ScanLine { text, x, y, w, h }` (0 to 1, top-left origin), `rows(lines)`, `read(text_rows) -> Vec<Found>` where `Found { class: OwnClass, unsure: bool }`.
- `crates/intportal-core/src/store.rs`: `Snapshot.school: Option<String>`; `forget_sis` keeps own sessions.
- `crates/intportal-core/src/backup.rs`: `own_classes: Vec<ClassSession>`.
- `crates/intportal-core/src/portal.rs`: `OWN`, `Field::School`.
- `crates/intportal-ai/src/timetable.rs`: the model's rewrite (C12).
- Shell commands: `save_class`, `delete_class`, `read_timetable`, `read_timetable_ai`, `start_own`, `own_schedule`, `leave_own`.
- Camera plugin: `Capture.lines: [{ text, x, y, w, h }]` beside `text`.

## Errors

- Saving a class fails a check: the editor shows the line from C3 under the field and keeps everything typed.
- The camera is denied, missing, or the scanner needs a download: the existing camera lines (041).
- No class found: C12.
- The school name is empty: "Type your school's name." and Start stays off.

## Motion and Reduce Motion

The editor and the scan sheet slide up like the deadline adder (300 ms, the app's ease) and cross-fade under Reduce Motion. Saving buzzes `done`; a refused save buzzes `fail`.

## Accessibility

Every control is at least 44 pt. Day chips are toggle buttons with `aria-pressed` and full day names as labels. The review list is a list; "Check this" is text, not only colour.

## Not in this spec

- Reading a weekly grid (days across, times down). Next, once list rows prove out.
- Bringing an own schedule's notes and decks into a portal account.
- Grades by hand.
- Any cloud reading of photos.
