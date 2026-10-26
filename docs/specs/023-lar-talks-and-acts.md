# 023 LAR talks freely, sees the week, and changes classes

**Status:** draft, wording to confirm

## What changes for the student

LAR stops refusing ordinary questions. It answers general questions and tutors homework, while still saying when an answer is not from the student's notes. When asked about time, it sees today's date and the next 7 days of the student's classes and deadlines. The student can also ask it to make a class vacant, online, moved or cancelled for a date, or to add an extra session; LAR shows a confirm card and nothing changes until the student taps Apply.

## Direction and references

- The original Mac app's assistant: tools `set_class_status` (vacant, online, regular) and `set_class_time`, every change an exception on top of the SIS schedule and reversible (`IntPortal/Sources/PUPSISPortalApp/Core/Assistant/AssistantEngine.swift`, `docs/legacy/FEATURES.md` "What the assistant can do").
- ADR 0003: the model picks the action, Rust resolves dates and runs existing commands, and the student confirms every write.
- The everyday-UX rule "the AI model only rewords; it never sets dates" stays true: dates and class ids in a proposal come from Rust, not from the model.

## Keep

- Confirm cards with Apply and Undo; no automatic mode (`src/lib/assis/apply.ts`).
- Rules first: due, classes and grades answered from data without the model (`crates/intportal-ai/src/{intent,due,assis}.rs`).
- Safety guards from spec 020 and #177: prompt-leak and injection refusal, the self-harm reply with 1553 and 0917-899-8727, a pointer to a professional for medical and legal questions, cheating declined (`crates/intportal-ai/src/scope.rs`).
- Own-data honesty: never invent a grade, a time, a professor or a deadline.
- The grounding check for questions about the student's notes (#183, `crates/intportal-ai/src/ground.rs`).
- The SIS schedule is never edited. Class changes are marks on top of it (`Snapshot.marks`, `crates/intportal-core/src/calendar.rs`), the same ones the class sheet sets today.

## Behaviour

**Talking more freely**

- **C1.** A general-knowledge question (not about the student's data, no note above the search floor) reaches the model and gets an answer. The reply ends with a short tag in the student's language: "(General answer, not from your notes.)" / "(Pangkalahatang sagot, hindi galing sa notes mo.)".
- **C2.** Homework, math and code questions get tutor mode: the model explains the idea, gives hints and steps, and may work a similar example. It does not write a full essay, assignment or program longer than 12 lines for the student to submit; when asked to, it says so in one line and offers the steps instead.
- **C3.** Greetings, thanks, jokes and how-are-you go to the model with the persona when a chat model is installed. Without a model (Light), the existing short canned replies stay.
- **C4.** The guards in Keep still answer without the model: injection and prompt leak, self-harm, medical and legal advice, cheating.
- **C5.** A question about the student's own grades, classes, deadlines or professors that the data cannot answer still gets the honest "I don't see that" reply, never a model guess.
- **C6.** A question about the student's notes keeps the grounding check; a general question (C1) skips it.

**Seeing the week**

- **C7.** When a question is about time or the schedule (when, today, tomorrow, this week, next class, free time, a weekday name, "may pasok ba", "anong klase"), the prompt gets a "Your next 7 days" block: today's date and weekday, then each day with its classes after marks and moves, deadlines (syllabus, eMabini, own), and busy events from connected calendars (spec 031) when that is on.
- **C8.** "Next week" or a date 8 to 14 days away widens the block to days 8 to 14. Nothing further ahead is ever sent.
- **C9.** The block is capped at 1,500 characters. When it would be longer, it keeps days in order and cuts the lowest-priority lines first: busy events, then the evening of later days.
- **C10.** Questions not about time never get the block.

**Changing classes**

- **C11.** LAR can propose six changes, each shown as a confirm card:
  - make a class **vacant** (no class) for one date;
  - make a class **online** for one date;
  - **move** a class to another day, time or room for one date;
  - **cancel** a class for one date (the same mark as vacant, worded "cancelled");
  - put a class **back to normal** for one date or for the rest of the term;
  - **add an extra session** (a one-off meeting of a subject), written as an event in the student's IntPortal calendar (spec 031).
- **C12.** "Every week", "from now on" and "for the rest of the term" apply the change to the whole term; the card says "For the rest of the term" in words before Apply.
- **C13.** Rust identifies the class (subject match from `intent::subject_in`, the day from the date table) and the date. When a subject meets more than once that day, or the date is ambiguous, LAR asks which one instead of proposing.
- **C14.** The card shows before and after in one line, for example "MATH 101 · Thu, Oct 29 · 8:00–9:30 AM → Vacant", and the scope ("This date only" or "For the rest of the term").
- **C15.** Apply calls the existing `set_mark` or `set_move` command (`src-tauri/src/lib.rs`); Undo restores the mark that was there before (not just "clear").
- **C16.** A move that ends before it starts, crosses midnight, or overlaps another class shows the problem on the card; an overlap can still be applied, the others cannot.
- **C17.** After Apply or Undo, class reminders and the phone-calendar class sync update the same way they do after a change from the class sheet.
- **C18.** Short commands work without the model through rules: "vacant ang MATH 101 bukas", "make CS 102 online on Friday", "move Math to 3pm Thursday", "balik sa normal ang Math". The model is only used for phrasings the rules do not catch, and its output is only an action name and the student's words; Rust fills ids, dates and times.
- **C19.** LAR never says a change was made before the student taps Apply.

## Copy

- General tag: "(General answer, not from your notes.)" / "(Pangkalahatang sagot, hindi galing sa notes mo.)"
- Tutor limit: "I won't write the whole thing for you to hand in, but here's how to do it." / "Hindi ko isusulat ang buong sagot na ipapasa mo, pero ganito ang gagawin."
- Card scopes: "This date only" / "Ngayong araw lang"; "For the rest of the term" / "Hanggang matapos ang term".
- Card actions: "Apply", "Undo", "Not now".
- Ambiguous class: "Which Math: the 8:00 lecture or the 1:00 lab?" / "Aling Math: ang 8:00 o ang 1:00?"
- Done line after Apply: "Done. MATH 101 on Thu, Oct 29 is vacant." / "Ayos na. Vacant ang MATH 101 sa Huwebes, Oct 29."

## Data shape

- `crates/intportal-ai/src/assis.rs` `Proposal` gains `MarkClass { session_id, week: Option<Date>, mark: Option<Mark> }`, `MoveClass { session_id, week: Option<Date>, slot: Option<Slot> }`, `AddSession { subject, date, start, end, room: Option<String> }`; `Facts` gains `week: Vec<DayView>` (date, classes after marks, due items, busy) filled only for time questions.
- `crates/intportal-ai/src/scope.rs`: `GeneralKnowledge` and `Homework` become routes to the model with a tag or tutor rule, not refusals; `Chitchat` goes to the model when installed.
- `crates/intportal-ai/src/persona.rs`: the "answer only from the facts" rule is scoped to questions about the student's data; a tutor rule and the general tag are added.
- `src/lib/assis/apply.ts`: apply and undo for the new proposals through `set_mark`, `set_move` and the calendar plugin's add (spec 031).
- Core needs nothing new for C11 to C17: `Marks.mode`, `Marks.moved`, `today::week` already exist.

## Errors

- Class not found: "I can't find that class in your schedule. Which subject?"
- Change failed (store error): "That didn't save. Try again from the class sheet." The card stays.
- Extra session when no IntPortal calendar access: "I need calendar access to add that. Turn it on in You → Calendar."

## Motion and Reduce Motion

Cards use the existing confirm-card motion; nothing new.

## Accessibility

The card's before and after line is one sentence for VoiceOver and TalkBack, for example "MATH 101, Thursday October 29, 8 to 9:30 AM, will be vacant, this date only".

## Out of scope

- An automatic mode that applies changes without a tap.
- Editing the SIS schedule itself.
- Changing or deleting events in the student's Google, iCloud or Outlook calendars (spec 031 keeps them read-only).
- Looking anything up online.

## Test map

| Criterion | Check |
|---|---|
| C1–C6 | `cargo test -p intportal-ai` scope routing with FakeLlm (general tag present, tutor limit, guards never call the model) and the out-of-scope suite (`crates/intportal-llm/examples/suite.rs`) re-baselined |
| C7–C10 | `cargo test` that a time question puts the block in the prompt and a non-time question does not; size cap test |
| C11–C14, C18, C19 | `cargo test` rules for each command phrase (EN and Filipino), ambiguous-class question, card text |
| C15–C17 | vitest for apply and undo through the mocked `set_mark` / `set_move` and the reminder reschedule |
| C16 | `cargo test` move validation |

## Open questions

1. Is 12 lines the right limit for code in tutor mode, and should essays have a word limit (for example 120 words) instead of "no full essay"?
2. Should "cancelled" be a separate mark from "vacant" so the class sheet can show the difference?
3. Should the general tag be dropped once the student turns it off in You?
