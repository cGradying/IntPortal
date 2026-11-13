# 040 Trust and speed

**Status:** approved (2026-11-03)

## What changes for the student

The app never shows something it doesn't know: no "Nothing scheduled" while it is still loading, no raw error text, and no login you can't fix. Every tab says how fresh its data is. The things students do every day take fewer taps: one button reviews every due card, a deadline opens straight to its outline, and a tap on a class means the same thing everywhere.

## Direction and references

- Part of the everyday-UX plan, range 040–049. North star: never miss a deadline. 041 is the deadline list; this spec is everything around it that makes the app trustworthy and quick.
- **Launch is not here.** The 2026-10-22 decision "a signed-in launch goes straight to Today" was replaced on 2026-10-25 by the dive plan (`docs/specs/PLAN-dive-environment.md`, branch `docs/plan-dive-environment`): the dive is the loading screen, at least 0.6 s, and Reduce Motion goes straight to Today. That plan owns launch.
- **Calendar views follow the dive plan's mockups.** C13 (week navigation) holds whatever those views become.
- The trust bugs already filed carry over as criteria: #158 (C1), #159 (C3), #160 (C5). Their PRs cite these ids once this spec is approved. Until then they ship as bug fixes.
- PRODUCT.md: glance first, two taps or fewer. Copy is LAR's voice: friendly, clear first, light Taglish.

## Keep

- Pull to sync, and the offline card's "Showing what was saved <time>" (`Today.svelte:115`).
- Long press on a class for the class sheet (`Today.svelte:227`). C12 makes tap consistent; the long press stays.
- The per-deck study modes (Flashcards, Type it, Choices).
- The sign-in guard's limits (3 tries per 15 minutes, none by itself after a rejection).

## Behaviour

**Trust**

- **C1.** Leaving a subject page by any route (Done, the Notes tab, Android back, opening a note) saves unsaved grading, target and outline edits first. (#158)
  *Built 2026-11-14:* `leave()` in `leave.ts`: Done, back and the Notes tab save first; vitest `c1_notes_tab_saves_first`.
- **C2.** While Today's data is loading (`app.today` is null), Today shows skeleton rows in the hero and the agenda. "Nothing scheduled" appears only when today's data has loaded and has no classes.
  *Built 2026-11-14:* Today's agenda shows `Skeleton` while `app.today` is null.
- **C3.** No card says "nothing due" without data. "Never synced", "sync failed" and "nothing due" are different states (#159; 041 C9 takes this over for the Due card).
  *Built 2026-11-14:* `knowsNothingDue` needs a connected source and a sync in the last day from each; `MabiniPage` uses it; vitest `c9_three_states`.
- **C4.** Every error the core returns is shown in plain copy from one map (`src/lib/errors.ts`), never as raw core text. An error the map doesn't know shows "Something went wrong. Try again in a bit." and logs the raw text to the console only.
  *Built 2026-11-14:* `errors.ts` has the spec copy (time in the too-many-tries line, from the core's message); only the app's listed sentences pass through; raw `String(e)` sites route through `friendly()`, except `ClassSheet` (other PR); vitest `c4_friendly_maps_known_errors_and_falls_back`.
- **C5.** When the SIS rejects the saved login, Today and You offer **Update password**. It opens the sign-in form pre-filled with the student number and an empty password. A new password clears the rejection and syncs once. The same applies to eMabini (#160, #130).
  *Built 2026-11-14:* Today offers Update password for eMabini too; it opens You on the Accounts page, with `PortalConnect` prefilled.
- **C6.** The header of each tab (Today, Schedule, Grades) shows "Synced <ago>" from the last SIS sync, on every phone, not only on phones without a Dynamic Island. Tapping it syncs.
- **C7.** Every tappable control is at least 44 by 44 pt and has a label that reads correctly with VoiceOver (#66). This includes the deck back button, the card ×, LAR sheet header buttons, colour swatches and term chips.
- **C8.** Notes can be deleted from the note editor (**Delete note**, with a confirm). Deleting removes the note from the AI index too.

**Speed**

- **C9.** On Study, **Due now** is a button. It starts one session with every due card across all decks, oldest due first. With nothing due it is disabled and reads "Nothing due".
- **C10.** A study session started from Due now shows each card's deck name above the card.
  *Built 2026-11-14:* `StudySession` takes `all`, so one due deck still shows its label and goes oldest first (`dueQueue.ts`); vitest `c9_due_cards_across_decks_oldest_first`.
- **C11.** Opening a subject from a deadline (Today's Due card, LAR's deadline nudge, a deadline reminder) opens it on the Outline tab, scrolled to that item.
  *Built 2026-11-14:* Deadline reminders open `subject:<code>[:<item>]`, routed in `openFromNotification`; `cargo test c11_reminders_open_the_subject`, vitest `c11_deadline_reminder_opens_the_subject_outline`.
- **C12.** Tapping a class does the same thing on Today and Schedule: it opens the class sheet. The sheet's **Syllabus & grading** row opens the subject. A long press stays a shortcut to the class sheet on Today.
- **C13.** Schedule can move to the previous and next week (arrows, and a swipe on the week header). **This week** returns. Marks and moves for that week show as they apply.
- **C14.** Freeform notes and note search are reachable from the Study tab (**Notes**), not only at the bottom of You.

## Copy

- Skeleton: no text.
- Synced: "Synced just now", "Synced 5 min ago", "Synced yesterday".
- Unknown error: "Something went wrong. Try again in a bit."
- Rejected login: "The SIS turned your login down. Changed your password?" **Update password**
- eMabini rejected: "eMabini turned your login down." **Update password**
- Due now: **Review all due (24)**; disabled: "Nothing due".
- Schedule: **This week**, accessible labels "Previous week" and "Next week".
- Note: **Delete note**; confirm "Delete this note? This can't be undone." **Delete** / **Cancel**.
- The error map's first entries (core text → copy):
  - "couldn't reach the SIS…" → "Can't reach the SIS right now. Showing what was saved."
  - TooManyTries → "Too many tries. You can try again at <time>."
  - NoSchedule → "The SIS has no classes for you this term yet."
  - SignedOut → "Your session ended. Pull to sync."

## Data shape

- `src/lib/errors.ts`: `friendly(raw: string): string`. It is a table of patterns to copy, plus the fallback (C4). It is used by `Landing.svelte:104`, `PortalConnect.svelte:34`, `state.svelte.ts` (sync errors) and `Grades.svelte:85`.
- `src/lib/SubjectPage.svelte`: one `leave(then)` path that saves when the page is dirty, used by Done, the Notes tab and back (C1). `openSubject(code, description, tab?, item?)` in `state.svelte.ts:172` takes an optional tab and item (C11).
- `src/lib/StudySession.svelte` accepts cards from many decks, each tagged with its deck. A core command `due_cards(now) -> Vec<(deck_id, deck_name, card)>` sits beside `study` in `src-tauri/src/lib.rs` and is built on `Deck::due` (`study.rs:121`). Reviews save to each card's own deck.
- `src/lib/screens/Schedule.svelte`: a `weekOffset` state, with `week` called for that week (`Schedule.svelte:21-31`).
- Notes: a `delete_note(key)` command in `lib.rs` that also drops the note's chunks (`store.rs` chunks table).
- No store changes.

## Errors

- **Review all due when a deck is deleted mid-session:** that deck's remaining cards are skipped quietly.
- **Update password with tries used up:** the form shows TooManyTries copy and the time, and the field stays filled.
- **Week navigation past the term's last class:** shows the empty week with "No classes this week".

## Motion and Reduce Motion

- Skeletons shimmer with the existing `Skeleton.svelte`, and are static under Reduce Motion.
- Week changes slide horizontally (200 ms) and cross-fade under Reduce Motion.
- Everything else uses existing motion.

## Accessibility

- C7 is the accessibility pass. VoiceOver labels are checked by reading every screen in the simulator.
- "Synced <ago>" is a button labelled "Last synced <ago>. Sync now."
- Due now announces its count.

## Out of scope

- Launch and the dive (the dive plan).
- Calendar look (the dive plan's mockups).
- The Due card and deadlines (041).
- LAR's day plan and the nudge cap (042).
- Widgets.

## Test map

| Criterion | Check |
|---|---|
| C1 | vitest `c1_notes_tab_saves_first` (failing first, #158) |
| C2 | vitest on Today's view state; screenshot of the skeleton |
| C3 | vitest `c9_three_states` in 041, or #159's test |
| C4 | vitest `c4_friendly_maps_known_errors_and_falls_back` |
| C5 | vitest on the error-to-action mapping; simulator run with a demo rejection |
| C6 | vitest on the "ago" formatter; screenshots on an iPhone with and without a Dynamic Island |
| C7 | simulator VoiceOver pass and a target-size check script over the built CSS (#66, #68) |
| C8 | `cargo test -p intportal c8_delete_note_drops_chunks`; vitest on the confirm |
| C9, C10 | `cargo test c9_due_cards_across_decks_oldest_first`; vitest on the session's deck label |
| C11 | vitest on `openSubject` with a tab and item |
| C12 | vitest that Today and Schedule tap handlers open the class sheet |
| C13 | vitest on `weekOffset`; screenshot of next week with a move |
| C14 | screenshot of Study's Notes entry |

## Decided

- C12: a tap on a class opens the class sheet on both Today and Schedule. One more tap to the syllabus from Today is accepted; the Due card (041) covers deadlines (user left it to the Head, 2026-11-03).
- C14: Notes lives on the Study tab, not a sixth tab.

## Built 2026-11-14 (C7, target sizes)

Fixed to at least 44 pt: the deck back button and card × (`DeckPage`), the Study back button, Grades term chips and goal inputs, `AddDeadline` title field and segmented buttons, and the buttons in `ErrorCard`, `NeedSis`, `SubjectPage` and `ThemeMaker`, and the Assis suggestion chips.

Check: `node scripts/tap-targets.mjs` lists CSS rules on buttons that set a height, min-height or width under 44 px (also run in vitest as `040_c7_no_button_rule_under_44px`). It is a heuristic: a hit area can come from padding or a parent, so it flags and a person reads. It skips files owned by other open PRs. Still open there: `ClassSheet`, `NoteEditor` (selection bar, segmented buttons), `Today` (offline button, coach ×), `Schedule` (segmented buttons), `You` (swatch). The VoiceOver pass stays manual in the simulator.
