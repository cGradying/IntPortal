# 022 Quiz me from my notes

**Status:** draft, wording to confirm. Open questions at the end need the user's answers before this is approved.

## What changes for the student

The student tells LAR "quiz me on this note" or "i-quiz mo ako sa Math". LAR asks one question at a time, taken from the student's own notes. The student answers in their own words. LAR says Right, Partly or Not yet, shows the note line that backs the verdict, and keeps a short score. At the end LAR can offer to turn the missed questions into deck cards, and only the student's tap saves them. Everything runs on the phone.

## Direction and references

- Spec [020-ai](020-ai.md): the chat sheet, source chips, confirm cards, "nothing is written without the student's tap". ADR 0003: on-device, opt-in, no AI command writes.
- `docs/ai.md`: at 1B-2B the model invents on questions the notes do not support (issue #138). So here the model never writes a question and never decides a verdict. Rules do both; the model may only write one short explanation, and the quiz works without it.
- Cards: the review step in `src/lib/assis/DeckCards.svelte` and `cards.ts` (`tidy`) are reused for "make cards from what I missed".
- Reference: `intent.rs` today reads the word "quiz" as a due-date question (`Intent::Due`). This spec adds a `Quiz` intent that wins when "quiz" is a request ("quiz me"), and leaves "when is my quiz" as Due.

## Keep

- Light is the default; nothing downloads because of a quiz.
- Source chips (020 C3), confirm cards ("Not now" or the gold button), Stop, New chat.
- Exact questions (due, classes, grades) are still answered by rules, not by a quiz.
- Nothing is written (a note, a card, a deck) without the student's tap.
- FSRS decks and card scheduling are untouched: a quiz result never changes a card's review date.

## Behaviour

**Starting and stopping**

- **C1.** "Quiz me", "quiz me on this note", "i-quiz mo ako", "quiz me on Math 101" and "test me on binary trees" start a quiz. "When is my quiz?" and "ano ang quiz ko bukas" do not; they are still answered as due dates.
- **C2.** The quiz covers one scope, chosen in this order: the open note; the subject named in the message (its class note and the notes of that subject); a topic named in the message (search hits above `rag::FLOOR`, notes only); else all the student's notes. LAR says the scope in its first line ("Quiz on MATH 101 · 5 questions").
- **C3.** A quiz is 5 questions unless the message names a number ("quiz me 10 questions", up to 10). If the scope holds fewer questions than asked, LAR says how many it found ("I found 3 in this note.") and asks those.
- **C4.** Stop is always on screen during a quiz and ends it at once. The messages "stop quiz" and "tigil na" do the same. Ending shows the score so far. Starting a new quiz while one runs asks nothing and ends the old one.

**Questions**

- **C5.** One question is on screen at a time. The next one appears only after the student answers, taps "I'm not sure", or taps "Skip". There is no timer.
- **C6.** Every question is built from one sentence or line in one of the student's notes, by rules, with no model. A sentence qualifies when it has 6 to 30 words, is not a heading or a question, and has an answer span (C7).
- **C7.** The answer span is found in this order: a definition ("X is Y", "X ay Y", "X means Y") asks "What is X?" and expects Y; a "Term: meaning" or "term - meaning" line asks for the term's meaning; else a fill-in-the-blank hides one number, or one capitalised term that is not the sentence's first word, or else the longest content word. The words around the blank stay exactly as the student wrote them.
- **C8.** Every question shows a source chip ("From: MATH 101 · Mathematics") before it is answered. Tapping it opens the note. A question without a source never appears.
- **C9.** A sentence is asked at most once in a quiz. The order is shuffled from a seed fixed at the start of the quiz, so a test reproduces it.
- **C10.** The model is never asked to write, reword or choose a question. The same notes and the same seed give the same questions with the model absent.

**Answering and grading**

- **C11.** The student types the answer in the chat box, whose label and placeholder become "Your answer" during a quiz. The box is not sent to the chat model.
- **C12.** The verdict is decided by rules on the expected answer words and the student's words, both lowercased, with punctuation, accents and Filipino/English stop words removed. A word matches if it is equal, or within one edit when it has 5 letters or more. A number must match exactly.
- **C13.** One expected word: it matches (Right) or it does not (Not yet). Several expected words: all matched or at least 80% (Right), at least 40% (Partly), less (Not yet). The answer may be in English, Filipino or Taglish.
- **C14.** The verdict word appears at once, before any model work, and the model is not called for Right.
- **C15.** Every verdict shows the note line that backs it, with the expected words marked, and the source chip again.
- **C16.** For Partly and Not yet, LAR may add one explanation of at most 160 characters, written by the model from the question, the note line and the verdict only (never the student's answer). It cannot change the verdict. If the model is not on the phone, is busy, fails, or writes nothing that shares a word with the note line, LAR shows the fixed sentence "The note says: {note line}." instead. The student sees no error.
- **C17.** "I'm not sure" shows the note line and the answer without a verdict. It counts as "not sure" in the score, not as wrong or right. "Skip" moves on and counts as neither.
- **C18.** If the student thinks the rules were too strict, "I was right" under a Partly or Not yet turns the verdict into Right. It can be used once per question and is counted as a student override in the score.

**Score and end**

- **C19.** A running score ("2 of 3 right") shows above the question and updates after each verdict. Partly and not sure are listed separately in the end summary, not folded into right or wrong.
- **C20.** The end summary says right, partly, not yet and not sure counts, and lists the topics (note titles) with the most misses. Nothing is graded as a mark and nothing appears in Grades.
- **C21.** A quiz in progress stays when the sheet is closed and opened again. When the app is closed, the quiz ends; the verdicts already given are kept (C25).

**Missed questions to cards**

- **C22.** When a quiz ends with at least one Not yet or not sure, LAR shows a confirm card: "Make cards from the {n} you missed?" with "Not now" and a gold "Review cards". Nothing is offered when nothing was missed.
- **C23.** "Review cards" opens the card review step with one draft per missed question: the front is the question as asked, the back is the expected answer and the note line. The student can edit, untick or add a draft. Partly questions are listed but unticked. Fronts the deck already has are dropped (`tidy`).
- **C24.** The deck is the subject's deck if there is exactly one for that subject; otherwise LAR asks which deck, or to make a new one named after the note. No deck or card is created until the student taps "Add {n} cards". "Not now" and closing the step save nothing.

**What is kept**

- **C25.** Each verdict is stored on the phone as: note key, a hash of the question sentence, the verdict, the time. The student's answer text and the note text are not stored. The last 200 verdicts are kept. (Depends on open question 1.)
- **C26.** Sign-out and wipe clear the quiz results. The IntAssis card has "Clear quiz results", which empties them after one confirm tap. New chat does not.
- **C27.** The chat shows one line when a quiz starts and one when it ends (the summary). The questions and answers are not chat turns, so a quiz does not push the real conversation out of the last 60 turns.

**What to review today**

- **C28.** When a note has at least 3 stored verdicts in the last 14 days and at least half of them are Not yet or not sure, the coach may show one line for the note with the most misses, at most once a day: "Math 101 notes: you missed 3 of 4. Quiz me on them?" The line says only what the quiz answers showed, never "weak", "failing" or a grade.
- **C29.** Tapping the line opens the chat sheet and starts the quiz on that note. Dismissing it hides it until the next day. There are no notifications and no badge. With no stored verdicts, or with Clear quiz results, no line appears. (Depends on open question 5.)

**When nothing can be asked**

- **C30.** With no notes at all: "You don't have notes to quiz yet. Write a few lines and I'll ask you about them." with a "New note" button. With a scope whose notes hold no qualifying sentence: "That note is too short to quiz. Add a few full sentences." With a subject that has no notes: "No notes for {subject} yet." With a topic that finds no hit above the floor: "I couldn't find notes about that. Try a subject, or open a note and ask again." LAR never makes up questions to fill the gap.

**Language, access, motion**

- **C31.** The session language is set from the message that started it (`is_filipino`). LAR's own words use that language; the question is the student's own sentence with a frame word in that language ("Ano ang…?", "Punan ang patlang:"). Verdict words are Right / Partly / Not yet or Tama / Medyo tama / Hindi pa.
- **C32.** Errors are one plain sentence in the student's language, no codes. Table below.
- **C33.** All buttons are at least 44 px high and reachable by keyboard and screen reader. The verdict is a word, never a colour alone. The question and verdict are announced once in a polite live region when they appear; after a verdict, focus moves to the "Next" button, and after Next, to the answer box.
- **C34.** Text follows the iOS text size like the rest of the chat. Under Reduce Motion the verdict appears without a fade and LAR holds still; with motion, the verdict fades in over 0.2 s and LAR nods once (stepped).
- **C35.** The whole quiz works with airplane mode on. No quiz data, note text or answer leaves the phone, and nothing about a quiz is logged with note text in it.

## Copy

English first, Filipino second. Follows `PRODUCT.md`: friendly, light Taglish, clear first. No emoji, no praise inflation.

| Where | English | Filipino |
|---|---|---|
| Start | "Quiz on {scope} · {n} questions" | "Quiz sa {scope} · {n} tanong" |
| Few found | "I found {n} in this note." | "{n} lang ang nakita ko sa note na ito." |
| Question frame (definition) | "What is {term}?" | "Ano ang {term}?" |
| Question frame (blank) | "Fill in the blank: {sentence with ____}" | "Punan ang patlang: {sentence with ____}" |
| Answer box | "Your answer" | "Sagot mo" |
| Buttons | "I'm not sure", "Skip", "Next", "Stop", "I was right" | "Hindi ako sigurado", "Laktawan", "Susunod", "Tigil", "Tama ako" |
| Verdicts | "Right" / "Partly" / "Not yet" | "Tama" / "Medyo tama" / "Hindi pa" |
| Note line label | "Your note says:" | "Sabi ng note mo:" |
| Fixed explanation | "The note says: {line}." | "Sabi ng note: {line}." |
| Not sure | "No problem. Your note says:" | "Okay lang. Sabi ng note mo:" |
| Score | "{r} of {n} right" | "{r} sa {n} ang tama" |
| End | "Done. {r} right, {p} partly, {m} not yet, {u} not sure." | "Tapos na. {r} tama, {p} medyo tama, {m} hindi pa, {u} hindi sigurado." |
| Cards offer | "Make cards from the {n} you missed?" Buttons "Not now", "Review cards" | "Gawing cards ang {n} na hindi mo nasagot?" "Mamaya na", "Tingnan ang cards" |
| Clear | "Clear quiz results" | "Burahin ang quiz results" |
| Review line | "{note}: you missed {m} of {n}. Quiz me on it?" | "{note}: {m} sa {n} ang hindi mo nasagot. I-quiz kita?" |
| Source chip | "From: {note heading}" | "Mula sa: {note heading}" |

## Data shape

- Rules, `crates/intportal-ai/src/quiz.rs` (new, pure, no model): `questions(notes, scope, seed, n) -> Vec<Question>`; `Question {key, sentence_hash, frame, prompt, expected: Vec<String>, line}`; `grade(&Question, answer) -> Verdict`; `Verdict::{Right, Partly, NotYet}`; `intent::Intent::Quiz`.
- Explanation: one grammar-forced call `{"why": string(maxLength 160)}`, `crates/intportal-ai/src/quiz.rs`, tested with `FakeLlm`.
- Commands, `src-tauri/src/ai.rs`: `quiz_start(now, message, openKey?) -> {scope, total, first}`; `quiz_answer(id, text, onText) -> {verdict, line, key, explain?}`; `quiz_unsure(id)`; `quiz_skip(id)`; `quiz_override(id)`; `quiz_stop() -> {summary, missed}`; `quiz_review() -> {key, title, missed, total} | null`; `quiz_clear()`.
- Storage, `crates/intportal-core/src/store.rs` (Core reviews): table `quiz(note_key, line_hash, verdict, at)`, last 200 rows, cleared by sign-out and wipe.
- UI hooks, `src/lib/assis/` (AI's own path): quiz card and score in the sheet. The coach line is a hook in the Today screen (UI). Cards reuse `DeckCards.svelte`.

## Errors

| Case | English | Filipino |
|---|---|---|
| Notes cannot be read | "I couldn't read your notes just now. Try again." | "Hindi ko mabasa ang mga note mo ngayon. Subukan ulit." |
| Topic search unavailable (no embedding model) | "I can quiz you on a note or a subject. Turn IntAssis on to quiz by topic." | "Kaya kitang i-quiz sa isang note o subject. I-on ang IntAssis para sa topic." |
| Explanation failed | Nothing is shown about it; the fixed sentence appears | Same |
| Cards could not be saved | "I couldn't save the cards. Try again." | "Hindi ko nasave ang cards. Subukan ulit." |
| Empty answer | "Type your answer, or tap I'm not sure." | "I-type ang sagot mo, o pindutin ang Hindi ako sigurado." |
| Another chat reply is running | "I'm still working on your last message. Give me a second." | "Ginagawa ko pa ang huli mong mensahe. Sandali lang." |

## Motion and Reduce Motion

The verdict fades in over 0.2 s on the shared ease; LAR nods once on stepped frames. Under Reduce Motion the verdict is simply there and LAR holds still. The score changes without a count-up.

## Accessibility

See C33. Source chips and "I was right" are real buttons with names ("Open note MATH 101", "Count my answer as right"). Larger text wraps the note line; it is never cut mid-sentence on the screen reader.

## Out of scope

Multiple choice, timers, streaks or leaderboards for quizzes, voice answers (the keyboard's dictation covers it), questions from deck cards, syllabus text or PDFs, grading long free-form paragraphs, scheduling quiz questions with FSRS, push notifications, and any score shown as a grade.

## Test map

| Criterion | Check |
|---|---|
| C1 | `cargo test -p intportal-ai quiz_intent_beats_due…`; `due` phrases stay Due |
| C2, C3 | `cargo test -p intportal-ai quiz_scope_order…`, `quiz_asks_fewer_when_notes_are_short…` |
| C4, C5, C21 | `vitest quiz` (state machine); simulator screenshot of Stop |
| C6, C7, C9, C10 | `cargo test -p intportal-ai questions_come_from_note_sentences…`, `questions_repeat_with_the_same_seed…`, `no_model_is_called_for_questions` |
| C8, C15 | `vitest quiz` chip and marked line; screenshot |
| C11 | `vitest quiz` (answer box is not sent to `ai_ask`) |
| C12, C13 | `cargo test -p intportal-ai grade_…` table of Taglish answers, typos, numbers, partials |
| C14, C16 | `cargo test -p intportal-ai verdict_before_model…`, `explanation_cannot_change_verdict…`, `explanation_falls_back…` with `FakeLlm` |
| C17, C18, C19, C20 | `vitest quiz` score and summary |
| C22–C24 | `vitest quiz` offer, `cards.test.ts` for `tidy`; screenshot of the confirm card; nothing saved until Add |
| C25, C26 | `cargo test -p intportal-core quiz_results_keep_200_and_clear…` |
| C27 | `cargo test -p intportal-core the_chat_keeps_sixty_turns…` stays green with a quiz run |
| C28, C29 | `cargo test -p intportal-ai review_picks_the_note_with_most_misses…`; screenshot of the coach line |
| C30, C32 | `vitest quiz` empty states and errors, EN and Filipino |
| C31 | `cargo test -p intportal-ai quiz_language_follows_the_first_message…` |
| C33, C34 | screenshots at 1.8× text; VoiceOver and Reduce Motion pass on the simulator |
| C35 | read the code path: no network call in `quiz_*`; airplane-mode run |

## Open questions

1. **Is the score stored?** Recommended: yes, as C25 (verdict, note, time; no answer text, no note text, last 200), because the "what to review today" line needs it. If no: drop C25, C26, C28, C29, and the score lives only for the one quiz.
2. **Does a quiz need IntAssis?** Recommended: no. Note and subject quizzes use rules only and work in Light; the explanation (C16) and quiz by topic need the model. Does Light get the LAR chat sheet at all for this, or is a quiz entry only shown after "Add IntAssis"?
3. **Length.** Default 5, up to 10 by saying so (C3). Fine, or fixed at 5?
4. **Missed to cards (C23, C24).** Are Partly cards listed but unticked right? Which deck when the subject has several: ask, or always make a new one named after the note?
5. **What to review today.** Ship it in the same build, or a second PR after Quiz works? It needs a hook in the Today coach line (UI) and the `quiz` table (Core), so I would file two handoff issues. Are the thresholds (3 verdicts, 14 days, at least half missed, once a day) right?
6. **"I was right" (C18).** Keep the override, or is it too easy to game? It exists because rules are strict on a student's own wording.
7. **Name.** `CONTEXT.md` says a quiz is a mode of reviewing a deck and tells us to avoid "quiz" for the deck itself. This feature is about notes, not decks. Keep the word "quiz" in the UI and add a CONTEXT.md line, or call it something else?
8. **Notes to subjects.** C2 says "the notes of that subject". The notes table has class and day notes; how a free note belongs to a subject needs Core's answer before the build.
9. **Copy.** Every string in the Copy table needs the user's wording, especially the Filipino lines.
