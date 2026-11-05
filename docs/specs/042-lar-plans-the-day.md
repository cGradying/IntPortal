# 042 LAR plans the day

**Status:** approved (2026-11-03)

## What changes for the student

LAR turns the day's free time into one concrete plan: "Free 1–3 PM: start Lab 4 (due tonight), then 8 COMP cards", which starts with one tap. A class reminder offers five cards for that class first. When a class ends, LAR offers to add today's entry to its note. On Grades, each subject says what score is still needed. On Sunday evening, LAR sums up the week ahead. Across all of this, the phone buzzes at most three times a day for anything that isn't a class, and never at night.

## Direction and references

- This is the third spec of the everyday-UX plan (040–049). It builds on 041's one deadline list (`crates/intportal-core/src/deadline.rs`, #202) and 040's Review all due (C9).
- Rules first. The plan, the lines and the budget are rules in the Rust core and work without the AI model. Rewording by the model is out of scope.
- The grilling decisions it follows (2026-10-22):
  - Today stays a glance with **one** LAR card.
  - At most 3 nudges a day, class reminders excluded, ranked deadline, then warm-up, then note after class.
  - Quiet from 10 PM to 7 AM.
  - One switch per type.
  - Exam radar is dropped.
- LAR's voice comes from PRODUCT.md: friendly, clear first, light Taglish, factual. Nothing it says is invented.

## Keep

- The coach's one-nudge-a-day card on Today, its dismiss-for-today, and the order of the existing nudges (`coach::pick`).
- Class reminders: their lead time, quiet for vacant weeks, and never capped or moved.
- The deadline and study-day reminder times on You.

## Behaviour

**Gap plan (Today's LAR card)**

- **C1.** The core finds today's free gaps: the time between two classes, minus the student's own calendar events. A gap counts when 30 minutes or more of it is still ahead.
- **C2.** When a counted gap is in progress or next, and there is something to do, the coach's nudge is a **plan** for that gap. It names the gap's time and, in this order:
  - the soonest deadline from 041's list that is overdue or due within 3 days;
  - that deadline's subject's due cards. If it has no subject or no due cards, it falls back to the due cards across decks.

  The cards fit the time left: 8 cards per 30 minutes after the deadline's share.
- **C3.** The plan's line reads "Free 1–3 PM: start Lab 4 (due tonight), then 8 COMP cards." Variants:
  - no deadline: "Free 1–3 PM: 12 cards fit. Kaya mo 'yan.";
  - no cards: "Free 1–3 PM: start Lab 4 (due tonight)."
- **C4.** Tapping the plan starts it. A deadline opens the way 041 C8 does (its outline, or eMabini). With cards only, it starts a review of those cards (040 C9's session, filtered to that subject).
- **C5.** The plan outranks the coach's existing Deadline and UseTheGap nudges while its gap is ahead. With no gap, or nothing to do, the existing nudges apply unchanged. Dismissing it hides it for the rest of that gap.

**Warm-up before class**

- **C6.** A class reminder for a subject whose deck has cards due adds a line: "COMP 20073 in 15 min · Review 5 cards?" It is still one notification and doesn't count against the cap.
- **C7.** Tapping that reminder opens a 5-card review of that subject's due cards. Tapping a plain class reminder opens Today, as now.

**Note after class**

- **C8.** Five minutes after a class ends, a notification says "COMP 20073 just ended. Add today's note?" It only fires for a subject whose class note the student has written in before.
- **C9.** Tapping it opens the class note with today's dated entry added (030 C11, C14).

**Grade risk**

- **C10.** On Grades and on a subject's Grading tab, each subject with a grading system shows one line from its tally:
  - **On track:** "On track for 90%."
  - **Needed:** "Needs 84% on what's left for 90%."
  - **Out of reach:** "90% is out of reach. Best now: 86%." This applies when the score needed is over 100.
  - **Done:** "All graded: 88%." This applies when nothing is left to score.
- **C11.** A subject with no grading system shows nothing. The target is the subject's own target, or 90% when none is set (the SubjectPage default).

**Sunday brief**

- **C12.** At 6 PM on Sunday, if anything from 041's list is due in the coming Monday–Sunday, a notification sums up the week: "Week ahead: 3 due, 1 exam. Heaviest: Wed." Tapping it opens Today.
- **C13.** The heaviest day is the one with the most deadlines plus classes. On a tie, the earlier day wins.

**Budget and quiet hours**

- **C14.** Every notification that isn't a class reminder goes through one core budget:
  - **The cap:** at most 3 per local day.
  - **The ranking when over:** deadline (evening-before and 8 AM), then the Sunday brief, then the study day, then note after class. The lower ones are dropped for that day.
- **C15.** Nothing from the budget fires between 10 PM and 7 AM. A heads-up that falls in that window moves to 7 AM the same morning if it is still ahead of what it's about; otherwise it is dropped.
- **C16.** You has one switch per type:
  - Deadline heads-ups (existing)
  - Study days (existing)
  - Warm-up in class reminders (new, on)
  - Note after class (new, on)
  - Sunday brief (new, on)

## Copy

- Plan: "Free 1–3 PM: start Lab 4 (due tonight), then 8 COMP cards." Day words: "due tonight", "due tomorrow", "due Fri", "past due". Button **Start**.
- Plan, cards only: "Free 1–3 PM: 12 cards fit. Kaya mo 'yan."
- Warm-up: "<code> in 15 min · Review 5 cards?"
- Note after class: title "<code> just ended", body "Add today's note?"
- Grade risk: as C10.
- Sunday brief: title "Week ahead", body "3 due, 1 exam. Heaviest: Wed." With one deadline: "1 due: Lab 4 (COMP 20073)."
- You: **Warm-up in class reminders**, **Note after class**, **Sunday brief**, with "At most 3 a day, none from 10 PM to 7 AM." under them.

## Data shape

- **`today.rs`:** `pub struct Gap { from: u16, to: u16, minutes: u16 }` and `gaps(items, now, busy) -> Vec<Gap>`, beside `free_minutes`. `free_minutes` becomes the sum of `gaps`.
- **`coach.rs`:**
  - `Signals` gains `gap: Option<Gap>`, `deadlines: Vec<Deadline>` (overdue plus 3 days; `due_soon` stays as the overdue-to-tomorrow part) and `cards_by_subject: BTreeMap<String, usize>`.
  - `Nudge::Plan { from, to, deadline: Option<PlanStep>, subject: Option<String>, cards: usize }`, where `PlanStep { id, title, when: String, url: Option<String> }`.
  - `pick` puts Plan first while its gap is ahead (C5).
- **`nudge.rs` (new, core):**
  - `pub enum Kind { Deadline, Brief, Study, AfterClass }`, ranked in that order.
  - `pub fn budget(list: Vec<(Kind, Reminder)>, per_day: usize) -> Vec<Reminder>` (C14, C15).
  - `pub fn brief(list: &[Deadline], sessions, marks, sunday: Date) -> Option<Reminder>` (C12, C13).
  - `pub fn after_class(sessions, marks, noted: &[String], now, days) -> Vec<Reminder>` (C8).
- **`today::reminders`** gains a `warm: &BTreeMap<String, usize>` argument (due cards per subject) for C6's line.
- **`Reminder`** gains `open: Option<String>`, a deep link the UI reads when the notification is tapped: `study:<code>:5`, `note:class:<code>`, `today`.
- **`src-tauri/src/lib.rs` `reminders`:** `ReminderPrefs` gains `warm_up`, `after_class` and `brief` (bools). The command builds the class reminders, runs everything else through `nudge::budget`, and returns one list. This is a hot file: one small PR.
- **Grade risk:** `syllabus::Tally` already has `needed`, `standing` and `target`. Add `pub fn risk(t: &Tally) -> Risk { OnTrack, Needs(f64), OutOfReach { best: f64 }, Done(f64) }`. `best` is the score if everything left scores 100.
- **UI:**
  - Today's LAR card draws the Plan with **Start**.
  - `state.svelte.ts` `scheduleReminders` passes the new prefs and puts `open` into each notification's `extra`. A notification-tap listener (`onAction` from `@tauri-apps/plugin-notification`) routes it.
  - Grades and SubjectPage draw C10.
  - You gets three switches.

## Errors

- **The notification permission is off:** nothing changes. You already shows the permission state.
- **A deep link to a deck or note that's gone:** opens Today.
- **A deadline marked done after its reminder was scheduled:** the next `scheduleReminders` run (every sync and launch) drops it. One stale heads-up can still fire before that.

## Motion and Reduce Motion

No new motion. Start uses the existing press and haptic.

## Accessibility

- The plan card is one button labelled with its full line plus "Start".
- Grade-risk lines are text, not colour alone. A colour hint, if any, follows the One Gold Rule.

## Out of scope

- The AI model rewording any line.
- Exam radar (dropped).
- Widgets and the Live Activity.
- Plans for tomorrow.
- A setting for the brief's time.

## Test map

| Criterion | Check |
|---|---|
| C1 | `cargo test -p intportal-core c1_gaps_cut_by_busy_and_now` |
| C2, C3 | `cargo test c2_plan_picks_soonest_deadline_then_subject_cards`, `c3_plan_lines` (all three variants) |
| C4 | vitest on Today's plan action routing |
| C5 | `cargo test c5_plan_outranks_deadline_while_gap_ahead`, `c5_no_gap_keeps_old_nudges` |
| C6 | `cargo test c6_warm_up_line_only_with_due_cards` |
| C7, C9 | vitest on the notification `open` router; simulator run tapping each notification |
| C8 | `cargo test c8_after_class_only_for_noted_subjects` |
| C10, C11 | `cargo test c10_risk_on_track_needs_out_of_reach_done`; screenshot of Grades |
| C12, C13 | `cargo test c12_brief_only_with_work_due`, `c13_heaviest_day_tie_goes_earlier` |
| C14 | `cargo test c14_budget_caps_three_by_rank` |
| C15 | `cargo test c15_quiet_hours_move_or_drop` |
| C16 | vitest on the prefs passed to `reminders` |

## Decided

- C8: note after class fires only for subjects whose class note the student has written in (user left it to the Head, 2026-11-03).
- C12: the brief is fixed at 6 PM Sunday, with no setting.
