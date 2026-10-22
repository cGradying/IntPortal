# 041 One deadline list

**Status:** draft

## What changes for the student

Every deadline the student has is in one list, wherever it came from: the syllabus they typed, eMabini, or one they add themselves by typing or by taking a photo of the board. That one list shows up on Today, in the evening-before reminders, in LAR's nudge and answers, and in the phone's calendar. When there is nothing due, the app says so only when it actually knows.

## Direction and references

- North star of the 040–049 range: never miss a deadline (the UX plan's grilling decisions, 2026-10-22).
- This spec takes over 030 C6–C10 (syllabus deadlines in the calendar). 030 keeps C1–C5 and C11–C14. Issue #148 is re-scoped to this spec.
- Rules first. Everything here works without the AI model. The model is never asked for a date ([020](020-ai.md), `intent.rs` "The model never computes dates").
- Logic lives in the Rust core with a test. The phone draws what the core returns ([ARCHITECTURE.md](../ARCHITECTURE.md)).
- Nothing is saved without the student's tap. The camera is off until the student opens it.

## Keep

- The syllabus outline, its items and their `done` checkbox (`syllabus.rs` `Item`).
- Opening an eMabini deadline opens it in eMabini (`MabiniDue.svelte`, `openLink`).
- The evening-before reminder time setting on You (`ReminderPrefs.deadlines`).
- The overdue-first ordering and the day words from `src/lib/deadlines.ts` (`dueLabel`, `titleOf`).

## Behaviour

**One list**

- **C1.** The core builds one deadline list from three sources:
  - syllabus quizzes, exams and projects that have a date and aren't done;
  - eMabini deadlines from the last sync;
  - the student's own deadlines.

  It is sorted by due time. A date-only deadline counts as due at 11:59 PM that day.
- **C2.** Each deadline has a stable id: `syl:<code>:<item id>`, `mab:<eMabini id>` or `own:<id>`. The id survives syncs, so reminders and calendar events never duplicate.
- **C3.** An eMabini deadline is matched to a class when its course's subject part (`split_course_name`) equals or contains a class's subject code. Otherwise it keeps the course name and has no subject.
- **C4.** Overdue deadlines stay in the list for 3 days after they were due, marked Overdue, and then drop out.

**Done**

- **C5.** Any deadline can be marked Done with one tap.
  - A syllabus item: this ticks its existing `done`.
  - An eMabini or own deadline: this records its id in the store.

  Done hides the deadline from Today, reminders, the calendar and LAR at their next refresh.
- **C6.** Done shows an **Undo** for 5 seconds. Under Today's card, a "Done this week" row lists the done ones and can un-mark each. An eMabini Done stays until the student undoes it, even if eMabini still lists the work.

**Today**

- **C7.** Today has one **Due** card in place of the two current ones (eMabini, and "Coming up this week").
  - It shows overdue deadlines first, then the next 7 days, at most 5 rows.
  - Each row shows the day word, the title, and the subject or course.
  - There is an **All deadlines** link.
- **C8.** Tapping a syllabus or own deadline opens its subject on the Outline. Tapping an eMabini one opens it in eMabini. A long press offers Done.
- **C9.** The card tells three states apart, and never says "nothing due" without data:
  - **Nothing due:** LAR "Walang due this week. Ayos!" This shows only when every connected source has synced within the last 24 hours.
  - **Not synced:** "eMabini hasn't synced yet", with a **Sync** button. This shows when eMabini is connected but has no `last_synced`, and the rest of the list still shows.
  - **Sync failed:** "Couldn't reach eMabini. Showing what we had at <time>." This shows when the last eMabini sync errored, and the rest of the list still shows.

**Add your own**

- **C10.** The Due card has an **Add** button. It opens one text field, "What's due?", with a paste button.
- **C11.** The student types or pastes free text (for example "quiz COMP fri" or a group-chat message). The core reads three things from it:
  - **the date:** `resolve_when`, extended to short weekday names ("fri", "lun") and to dates like "Oct 24" and "10/24";
  - **the subject:** LAR's `subject_in` (`intent.rs:70`);
  - **the kind:** the words quiz, exam, project, report or assignment; anything else is Project.

  What's left becomes the title.
- **C12.** A confirm card shows the title, date, subject and kind, each editable. **Save** adds it, and **Cancel** discards it. Nothing is saved before Save.
- **C13.** With no date found, the confirm card asks for one with a date picker, and Save stays disabled until a date is set. With no subject found, the subject is "None", and the student can pick one.
- **C14.** The student can edit or delete an own deadline from All deadlines.

**Camera**

- **C15.** The Add sheet has a **Scan** button. It opens the camera. The student frames the board, handout or screen and takes one photo.
- **C16.** The phone reads the photo's text on the device:
  - iOS: Vision `VNRecognizeTextRequest`;
  - Android: ML Kit text recognition, bundled model.

  The photo is never saved or sent anywhere, and it is dropped once its text has been read.
- **C17.** The recognised text goes through C11. If it has several dated lines, each becomes its own confirm row with a checkbox, all checked. **Save** adds the checked rows.
- **C18.** The first Scan asks for camera permission with the copy below. If permission is denied, the Scan button explains this and points to Settings, and typing still works.

**Everywhere else**

- **C19.** The evening-before reminders cover all three sources, at the student's deadline time. An eMabini deadline due before noon is reminded the evening before. One due at noon or later is also reminded at 8 AM on the day. (The daily cap on nudges comes with spec 042. Until then, reminders follow the existing switch.)
- **C20.** LAR's deadline nudge (`coach::Nudge::Deadline`) and IntAssis's due facts (`facts_for`) read the one list. "Ano ang due ko this week?" includes eMabini and own deadlines.

**Calendar (was 030 C6–C10)**

- **C21.** Each deadline in the list goes into the IntPortal calendar:
  - date-only deadlines are all-day events;
  - timed ones (eMabini) are 30-minute events that end at the due time.

  They are titled `<subject or course> <Kind>: <title>` ("COMP 20073 Quiz: Loops").
- **C22.** Done, deleted and undated deadlines leave the calendar at the next refresh. A refresh never duplicates an event, because each event is keyed by the deadline id (C2).
- **C23.** Deadline events follow the existing calendar setting. With it off, neither classes nor deadlines are written.
- **C24.** **Add classes to calendar** (the `.ics` share) includes the same deadlines: all-day ones as `DTSTART;VALUE=DATE`, timed ones as a UTC `DTSTART` and `DTEND`.

## Copy

- Today card: **Due**, **All deadlines**, **Add**, **Done**, **Undo**, "Done this week".
- Nothing due: LAR "Walang due this week. Ayos!"
- Not synced: "eMabini hasn't synced yet." **Sync**
- Sync failed: "Couldn't reach eMabini. Showing what we had at 3:40 PM."
- Add sheet: "What's due?", placeholder "quiz COMP fri, or paste the GC message". Buttons **Paste**, **Scan**.
- Confirm card: **Save**, **Cancel**. No date: "When is it due?" No subject: "Subject: None".
- Camera permission: "IntPortal reads the text in one photo, on your phone. The photo isn't kept."
- Camera denied: "Camera is off for IntPortal. Turn it on in Settings, or type it instead."
- Calendar event title: `COMP 20073 Quiz: Loops`.

## Data shape

```rust
// crates/intportal-core/src/deadline.rs (new)
pub enum Source { Syllabus, Mabini, Own }
pub enum Due { Day(Date), At(i64) }                 // At = epoch seconds
pub struct Deadline {
    pub id: String,                                  // C2
    pub source: Source,
    pub subject: Option<String>,                     // C3
    pub course: Option<String>,                      // eMabini course when no subject
    pub title: String,
    pub kind: syllabus::Kind,                        // eMabini: quiz → Quiz, else Project
    pub due: Due,
    pub overdue: bool,                               // C4
    pub url: Option<String>,                         // eMabini only, https
}
pub struct OwnDeadline { pub id: String, pub title: String, pub subject: Option<String>, pub kind: syllabus::Kind, pub date: Date }

pub fn deadlines(snap: &Snapshot, mabini: &MabiniData, now: Moment, utc_offset: i32, days: i64) -> Vec<Deadline>;
pub fn reminders(list: &[Deadline], now: Moment, minute: u16, utc_offset: i32, days: i64) -> Vec<Reminder>;   // C19
pub fn parse_own(text: &str, today: Date, subjects: &[(String, String)]) -> Draft;                           // C11, C13
```

- **Store.** `Snapshot` gains `own_deadlines: Vec<OwnDeadline>` and `done: BTreeSet<String>`, both `#[serde(default)]` so existing stores load. Sign-out keeps both, like notes and syllabus pages. "Erase everything" removes them.
- **Migration.** Callers move to the new list, and the old paths are deleted in the same PR:
  - `coach::Signals.due_soon` becomes `Vec<Deadline>`;
  - `syllabus::deadline_reminders` is replaced by `deadline::reminders`;
  - `syllabus::due` stays private to `deadlines`;
  - `ai.rs` `facts_for` reads `deadlines`.
- **Parser.** `parse_own` lives in the core. It moves `resolve_when` and `subject_in` from `intportal-ai/src/intent.rs` into `intportal-core`, and `intent.rs` calls the core versions. The date rules then have one home.
- **Commands** in `src-tauri/src/lib.rs`, a hot file (TEAM.md, Working in parallel), so this waits for #60 or goes in one small PR:
  - `deadlines(now, days)`;
  - `set_done(id, done)`;
  - `add_own(draft)`, `edit_own(own)`, `delete_own(id)`;
  - `parse_own(text, today)`.

  They replace `due` (`lib.rs:713`) and its one caller (`Today.svelte:34`).
- **Calendar.** `calendar.rs` `ClassEvent` gains `all_day: bool`. A new `deadline_events(&[Deadline])` sits beside `class_events`, and `ics` takes the deadlines too. In `plugins/tauri-plugin-calendar`, the Swift and Kotlin halves write `isAllDay` / `ALL_DAY`.
- **Camera.** A new `plugins/tauri-plugin-scan` has one command, `scan() -> { text: String }`:
  - iOS: `VNRecognizeTextRequest` on a photo from `UIImagePickerController` (camera source), with `NSCameraUsageDescription` set from C18's copy;
  - Android: ML Kit `com.google.mlkit:text-recognition` (bundled) on a photo from `ActivityResultContracts.TakePicture`.
- **UI.**
  - `src/lib/DueCard.svelte` replaces `MabiniDue.svelte` and Today's `.due` section.
  - `src/lib/AddDeadline.svelte` holds the sheet and the confirm card.
  - `src/lib/deadlines.ts` keeps `dueLabel` and `titleOf`, which now work on `Deadline`.

## Errors

- **eMabini sync failure or no sync:** C9's copy. The SIS and own deadlines still show.
- **Paste with an empty clipboard:** nothing happens and the field stays focused.
- **Scan finds no text:** "Couldn't read any text. Try closer, with more light." The student stays on the Add sheet.
- **Calendar permission denied:** no events are written, the same as for classes today.
- **A Done id whose deadline is gone** (dropped by eMabini, or a syllabus item deleted): it is ignored and pruned on the next save.

## Motion and Reduce Motion

- Done slides the row out (160 ms). It fades instead under Reduce Motion.
- The confirm card rises with the existing sheet motion.
- Done and Save play the "success" haptic.

## Accessibility

- Each row is one button labelled "<title>, <subject>, due <day word>". Done is also offered as a VoiceOver custom action, so it doesn't need a long press.
- Add, Paste, Scan, Save and Undo are at least 44 pt.
- The Undo toast is announced, and stays up while VoiceOver focus is on it.
- The date picker and fields have visible labels and follow Dynamic Type.

## Out of scope

- The daily cap on nudges and quiet hours (spec 042).
- Widgets and the Live Activity (no paid Apple account).
- Sharing deadlines with classmates.
- Writing anything back to eMabini.
- Recurring own deadlines.
- Reading deadlines with the AI model. The model may only reword LAR's lines, never set a date.

## Test map

| Criterion | Check |
|---|---|
| C1, C2, C4 | `cargo test -p intportal-core c1_three_sources_one_sorted_list`, `c2_ids_stable_across_sync`, `c4_overdue_drops_after_three_days` |
| C3 | `cargo test c3_mabini_course_matches_subject_code` |
| C5, C6 | `cargo test c5_done_hides_everywhere` (list, reminders, deadline events); vitest on the card's Undo |
| C7, C8 | vitest on the Due card view model; screenshot on the Head sim, demo mode |
| C9 | vitest `c9_three_states`; screenshot of each |
| C11, C13 | `cargo test c11_parse_own` with "quiz COMP fri", "Exam sa Lunes CS 201", "report on 10/24", a pasted GC message, and text with no date |
| C12, C14 | vitest on the confirm card and on All deadlines |
| C15–C18 | simulator (iOS) and emulator (Android) run with a photo of a printed sheet; screenshot of the permission copy |
| C17 | `cargo test c17_many_dated_lines` |
| C19 | `cargo test c19_reminders_all_sources` (evening before; 8 AM same day for timed afternoon deadlines) |
| C20 | `cargo test -p intportal c20_facts_include_mabini_and_own`; `coach` test with a Mabini deadline |
| C21, C22 | `cargo test c21_deadline_events_all_day_and_timed`, `c22_done_leaves_calendar` |
| C23 | vitest on `refreshClassCalendar` with the setting off |
| C24 | `cargo test c24_ics_has_deadlines` |
| Calendar plugin | simulator and emulator screenshots of an all-day and a timed deadline in the phone's calendar |

## Open questions

- Should C4's 3 days of overdue be longer for eMabini, which sometimes accepts late work? The recommendation is the same 3 days for every source.
- Should the 8 AM same-day reminder for afternoon eMabini deadlines (C19) count toward 042's daily cap? The recommendation is yes, ranked as a deadline.
