# 063 LAR v3 screens and sharper quizzes

**Status:** approved

## What changes for the student

LAR's note and edit cards get their final look, and an applied change stays in the chat, dimmed, with Undo. Decks get a Quiz mode built from the study faces the student already knows. Make a quiz and Write wrong answers sit in the deck page's LAR box. A long answer's words appear as they stream, and the chat's header follows the student's theme. Quizzes get fewer bad wrong answers, and Keep going picks up where the answer stopped instead of starting over.

## Direction and references

- Spec 062 holds. This spec builds its screens (062 C5, C13, C14, C20–C22, C25) and fixes what its evals showed.
- The owner's design picks, round 1, 2026-11-27 (`reference/prototypes/lar-v3-picks.html`, logged in 062 Decisions). The owner's notes on the three items marked Needs work:
  - Quiz faces: "there's already a UI for this".
  - Deck page: "use the current UI for the AI".
  - Long answers: "add animation on text spawns". On the header: "the red part, can this be modified by theme customizer too".
- Round 2 asked only those three items; the choices are in Decisions.
- The 062 evals on Qwen3.5 2B, in `docs/ai.md`:
  - Only 9 of 22 quiz cards kept three wrong answers, and some kept ones were true.
  - In one test, Keep going started the topic over.

## Keep

- Everything 062 shipped: the rules, the cards' content, the confirm-first rule, Undo, and the call budget (062 C28).
- Flash, Type and Choice as they are. Quiz adds no new kind of screen.
- The deck page's LAR box (`DeckCards.svelte`) and its Make cards flow.
- The chat's sky header at one fixed size, with LAR on its edge (048 C7–C11).
- The theme maker's LAR colour (047 C12). When set, it still colours LAR and his header.

## Behaviour

### A. The cards in LAR's chat (round 1, picked)

- **C1. Note from our chat: Slab, refined.** The card opens at its title, not scrolled to the end.
  - Header: a pixel label, with the subject as a chip in the subject's colour.
  - Then the title, and under it "Made from the last part of our chat" when only part of the chat fit (062 C3).
  - The points are drawn as gold bullets, as the note editor draws them, not as typed "- ".
  - Save and Edit stay pinned at the bottom while a long note scrolls.
  - After Save the card shows "Saved" and an **Open note** button.
- **C2. Editing before it's saved: Two fields.** Edit turns the card into a title field over a text field, filled with the note. The second button reads **Done** and goes back to the preview, keeping the changes. Save works from either view.
- **C3. Change, Add to and Tidy: Word marks.** Inside a changed line, the words taken out are struck through and the words put in are marked gold. A line wholly added is gold, and one wholly removed is struck. Unchanged runs fold as 062 C13 says.
- **C4. Rename, Move and Delete: Old over new.**
  - Rename: the old name, struck through and dimmed, over the new name in gold.
  - Move: the old subject chip, struck, over the new chip outlined in gold.
  - Delete: the note's name, with its first lines fading out under it. The red button reads **Delete**.
- **C5. After Apply: Card stays, dimmed.** The card stays where it was, dimmed to 70%, with a line under it: "Changed" (or "Renamed", "Moved", "Deleted") and **Undo**. After Undo the line reads "Put back", in the plain caption colour, not the error colour.
- **C6. Which note do you mean?: Note rows.** One full-width row per candidate: the note's name, then a caption line with its subject and the day it was last changed, and a chevron on the right. Tapping a row marks it and asks again (062 C8).

### B. Quiz mode, from the study faces we have (round 2)

- **C7. Multiple choice is Choice.** It is the existing "Pick the meaning" face and tiles. The four options are the card's back and its three wrong answers. If the card has no wrong answers, it takes other cards' backs, as Choice does today.
- **C8. Identification is Type.** The existing Type face, unchanged.
- **C9. True or false, from the same parts.** Type's face, with the claim (the card's back or one of its wrong answers, half and half, 062 C21) as the big text and the term in the small label. Under it, True and False as two full-width tiles, stacked. Only existing Choice and Type parts are used.
- **C10. Where Quiz starts.** **Quiz** joins the deck page's mode buttons next to Flashcards, Type it and Choices. It is on with 4 or more cards (062 C21). Scores, times and heat are as 062 C22 says.

### C. The deck page, in the LAR box we have (round 2)

- **C11. Make a quiz** is the button already in the deck's LAR box (`DeckCards.svelte`, 062 C17). It doesn't move.
- **C12. Write wrong answers** sits in the same box, for a deck with 4 or more cards where some have no wrong answers. It writes only for those, so a stopped run can finish later (062 C20 said "none with wrong answers"; this replaces it).
  - While it runs, the box shows "N of M cards" and **Stop**, in the box's own look.
  - Hiding the app pauses it at the next card, and coming back resumes it (062 C29).
  - Write wrong answers is a third ghost button beside the box's existing ones. Tapping it opens the box with its "LAR is …" row, the count and Stop. Quiz joins the mode buttons, which go two by two.

### D. Long answers (round 2)

- **C13. Words appear as they come.** Each new word in LAR's bubble rises 4 px and fades in over 160 ms. The text never reflows as it appears, and Keep going's words come in the same way.
- **C14. The header follows the theme.**
  - The sky header's colours come from the worn theme.
  - The theme maker's LAR colour, when set, wins as today.
  - With no theme worn, the header keeps the school's colours.
  - With a theme worn and no LAR colour set, the header is drawn from the theme's accent (`larLook(hueOf(accent))`). No new control.

### E. Sharper quizzes

- **C15. Near misses, not paraphrases.** The wrong-answer prompt asks for answers that are false in one checkable detail: a wrong number, a wrong term, or a reversed relation. It gives one example of each. It still takes one call per 8 cards (062 C28).
- **C16. True or false needs a checkable claim.** A wrong answer is shown as a True or false claim only if it differs from the back in a number or a content word the back has. Otherwise that card is dealt as multiple choice or identification.
- **C17. Ship gate.** On the `examples/cards` quiz set, at least 15 of 22 cards keep three wrong answers. A hand check of 20 kept sets finds no wrong answer that is true. The numbers go in `docs/ai.md`. If the model can't reach 15 of 22, the gate and the numbers are reported to the owner, not lowered.

### F. Keep going continues

- **C18. It starts where the answer stopped.** Keep going hands the model the words already written as the start of its own reply (`generate_prefilled`), so it writes the next words, not a new answer. Still up to 400 tokens, at most twice, only on the newest answer (062 C25).
- **C19. Ship gate.** Of 5 long answers cut at their limit, none restarts the topic, and none repeats a full sentence already written. The numbers go in `docs/ai.md`.

## Copy

| Where | Text |
|---|---|
| Note card, part of the chat | Made from the last part of our chat |
| Note card, after Save | Saved · Open note |
| Edit view, second button | Done |
| After Apply | Changed · Undo / Renamed · Undo / Moved · Undo / Deleted · Undo |
| After Undo | Put back |
| Picker row caption | {subject} · changed {day} |
| Write wrong answers, running | {n} of {m} cards · Stop |
| Write wrong answers, stopped | Wrote wrong answers for {n} of {m} cards. |
| True or false tiles | True / False |

## Data shape

- No new stored data. `Card.wrong` (062) feeds C7 and C9. Applied and undone states are fields on the chat message (`src/lib/assis/assis.svelte.ts`).
- C18: `assis::more` builds its prompt with `generate_prefilled` (`crates/intportal-ai/src/llm.rs`).

## Errors

- Write wrong answers fails part way: the box keeps what was written and shows "Wrote wrong answers for {n} of {m} cards." with **Try again**.
- Keep going fails: the bubble keeps every word, and Keep going stays (as 062).
- Undo after the note was edited by hand: "There's nothing to undo" (062), in the caption colour.

## Motion and Reduce Motion

- Cards enter with the chat's existing card entrance.
- The dim after Apply takes the app's quick move duration.
- C13's word motion is short, and never moves text already placed.
- Reduce Motion: words just appear, the dim is instant, and the header sky holds still, as it does on the low-memory tier.

## Accessibility

- Struck and gold words also read "Removed:" and "Added:".
- True and False are full-width, at least 44 pt tall.
- Picker rows are buttons labelled with the name and the caption.
- The header's colours keep the title and status readable on the room's ground. The theme maker refuses a header colour that fails contrast, as it does for the accent.

## Out of scope

- LAR changing the calendar, deadlines or classes. That is spec 064, after its questions.
- Quiz me in the chat, one question at a time (062).
- A new study screen or a new card style for Quiz.

## Build order

1. `ui/lar-cards`: A (C1–C6). Round 1 is enough to start now.
2. `ai/quiz-accuracy`: E (C15–C17), with the eval numbers.
3. `ai/keep-going`: F (C18–C19), with the eval numbers.
4. `ui/quiz-mode`: B and C (C7–C12).
5. `ui/lar-motion`: D (C13–C14).

## Test map

| Criterion | Check |
|---|---|
| C1–C6 | vitest on the card states in `assis.test.ts` / `apply.test.ts`; simulator screenshots of each card, Night and Day, 320 and 430 wide |
| C3 | vitest: word marks for a changed line, a whole added line, a whole removed line, the fold |
| C7–C10 | vitest for the dealing (options from `wrong`, fallback to other backs, true/false half and half, no three in a row); a simulator run of a Quiz session |
| C12 | vitest: progress, Stop, pause when hidden, resume |
| C13 | screenshot frames of a streaming answer; Reduce Motion shows no motion |
| C14 | vitest on the header colours for: no theme, a theme with no LAR colour, a theme with one; a contrast check |
| C15–C17 | `gen` tests for the true-or-false rule; `examples/cards` quiz numbers and the hand check in `docs/ai.md` |
| C18–C19 | `assis` test with a stub: the prefill carries the words written; `examples/long` numbers in `docs/ai.md` |

## Open questions

None.

## Decisions

- **2026-11-27, round 2.** The owner: "choose what's ergonomically the best". Chosen, with the reason for each:
  - True or false is **C, claim, full-width tiles**: the biggest targets in thumb reach, one column to scan, and it meets the full-width rule.
  - The deck page is **A, a third button, the box runs it**: the action is visible on every old deck, Stop is a full-size button, and the progress lives in the box's existing spinner row.
  - Streaming words is **A, rise and fade**: the words stay legible while they arrive, it costs the least on a slow phone, and it is gone in 160 ms.
  - The header is **A, sky follows the accent**: it follows the theme with nothing new to learn, and a set LAR colour still wins.

