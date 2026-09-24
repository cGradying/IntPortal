# 11 — Quizzes, study map and syllabus

Status: approved design (prototype v2). Screens: **Quizzes** and **Syllabus** (sidebar, Study group).

## Reference
Prototype `intportal-v2.html`: `renderQuizzes()`, `deckCard()`, `drawMap()`, `pickMode()`,
`renderStep()`, `recap()`, `openGenerate()`, `openReview()`, `renderSyllabus()`, `#addSyl` flow.

## Current behaviour inventory (must keep)
Quizzes (`Views/Quiz/*`, `Core/Quiz/*`):
- Deck browser with streak ("N day streak", `PixelBadge(.streak)`), "Continue studying", decks
  grouped by `sourceQuery`, deck menu "Generate more… / Regenerate… / Rename / Delete" (delete
  confirms "This deletes the deck and its review history.").
- "Generate deck" (disabled with "Turn on IntAssis and pick a model in Settings first" when AI is
  off). Sources: Vault topic / Paste material / Import file (md, txt, pdf, docx, pptx). "Deck name —
  Auto-named from the source if left blank". Progress "Generating from chunk X of Y…", "Send to
  background", job banner (running / "…ready — N cards to review" Review · Dismiss / failed "Try
  again"). Card review sheet: Front, Back, Subject, accepted-answer chips, delete, banners for
  truncation, failed chunks and regenerate keep/fresh counts, "Save".
- Modes: Flashcards (Space, Again/Hard/Good/Easy → FSRS), Identification (type, accepted answers,
  "Why?"), Multiple Choice (distractors = other cards' backs), True or False, Matching (6-pair rounds;
  any miss = Again). "Needs ≥4 cards". End states "Nothing due in this deck." / "Session complete."
- FSRS via `FSRSAdapter`; review log `QuizReviewRecord`; streak via `StudyStats.advance`.

Syllabus (`Views/SyllabusView.swift`, import/review sheets, `Core/SyllabusStore.swift`):
- Table / Timeline, type pills Lecture/Quiz/Exam/Project, status Done/This week/Upcoming,
  "Generate quiz from …" on lectures, "Export deadlines to calendar", grading calculator
  ("Average X% on what's left to land at 90%." etc.), "Add syllabus" → Import file / Paste text /
  Generate from scratch, "Week 1 begins", "Extract" → "Extracting chunk N of M…" → review (grading
  breakdown + items) → "Add". Generated-syllabus disclaimer banner.

## UX changes (the upgrades)

Each reads data the app already stores. New logic goes in pure `Core/Study/` types with tests.

1. **Study in the gaps** (Today, spec 04). `GapSuggestion.make(gaps:decks:now:examDates:)` picks
   the deck with most cards due (ties → nearest linked exam), estimates minutes as
   `min(due × 2, gap remaining)`, and prefers Flashcards. Shown inside the free-time row: "Study in
   this gap: Number systems · 6 cards due · about 12 min of flashcards · midterm Sep 27" + Start.
2. **Exam countdown.** `ExamLink.decks(for: SyllabusItem, in: [QuizDeck])` matches a deck when its
   cards' `subject` equals the item's `subjectCode` **and** the deck name or `sourceQuery` shares a
   topic token with any lecture before the exam. Banner at the top of Quizzes for the nearest exam
   within 14 days: big day count, "Midterm · COMP 001 in 4 days", "Sep 27 from the syllabus · Number
   systems has 6 cards due, mastery 44%", "Study for it".
3. **Real mastery.** `Mastery.of(cards:)` = share of cards with `fsrs.reps ≥ 2`, `fsrs.stability ≥
   7` days and last rating ≠ Again. Replaces `1 − due/total` (which read 0% for new decks and reset
   daily). Shown as a bar + percent on each deck and in the map.
4. **Due forecast.** `DueForecast.next7(cards:from:calendar:)` → 7 counts by `fsrs.due` day. Drawn as
   dithered bars under each deck, labelled by weekday initial starting today.
5. **Card stacks.** Deck tiles draw a 3D stack (`rotation3DEffect(.degrees(52), axis: (1,0,0))`,
   layers offset 3pt): layer count = `min(9, 2 + due)`. Hover lifts the stack. The count is the
   information; the depth is how you see it.
6. **Study map.** `StudyMap.layout(subjects:topics:)` → isometric tiles. Regions = subjects (from
   the COR), tiles = syllabus lecture topics (fallback: deck names). Tile top color = subject mixed
   toward sheet by mastery; gold pip when mastery ≥ 70%; a tower rises on the topic an exam covers,
   taller as the exam nears (`1 + (5 − days) × 0.9` block heights, capped). Hover → "COMP 001 ·
   Number systems · 44% mastered · exam in 4 days". Click → the deck's mode picker, or Generate deck
   prefilled with the topic when no deck exists. Drawn in one `Canvas`; hit-testing on the diamond.
7. **Heatmap + weak list.** 13×7 pixel grid from `QuizReviewRecord.date` counts (4 levels).
   "Weak on": top 3 (deck · card front) by Again count in the last 30 days.
8. **Distinct modes** (each its own view, shared header: Done, deck, pixel progress bar, "3 / 5",
   "· N correct", Auto-advance toggle):
   - Flashcards: 3D flip card (Space / click), Again · Hard · Good · Easy with the interval under
     each (from `FSRSAdapter` preview), keys 1–4, citation "from: {note} ▸ chunk n" on the back.
   - Identification: prompt = back, type the term, Check, "Why?" when wrong.
   - Multiple Choice: 2×2 options with keys 1–4, correct/incorrect colored, "Why?".
   - True or False: two big buttons, keys T / F.
   - Matching: 4×2 tile board; selected tile lifts; correct pair pops and clears; miss shakes.
   - **Auto-advance** after a correct answer becomes a toggle (critique finding), default on.
9. **Session recap** replaces "Session complete.": accuracy %, "N correct · M again", streak flame
   filling "5 → 6 day streak", and per card "Good · in 3 days" from the new FSRS due date. Actions
   "Study again", "Back to decks".
10. **Syllabus is editable.** "Mark done" / "Undo" per item writes `completedOverride`; a gold
    "This week · Week N" line sits in the timeline; lectures get "Quiz me" (opens Generate deck
    prefilled); exams show "Sep 27 · 4 days · 23 cards due across linked decks". Items can be edited
    and deleted (sheet reuse of the review row).

## Layout & components
- Quizzes: header row (streak left, Generate deck right) · job bar slot · exam banner · two
  columns: Study map sheet (1.4) | Last 13 weeks + Weak on sheet (1) · deck grid (auto-fill 210pt).
- Session: centered 760pt column.
- Syllabus: toolbar (subject segmented, Export deadlines, Add syllabus) · two columns: Timeline
  sheet | Grading calculator sheet.
- Generate / Add syllabus / Review: dialogs (notch, 560pt), Esc closes.

## States
- AI off: Generate deck disabled with the existing tooltip; Quiz me hidden.
- No decks: empty state "No decks yet — generate one from a topic or your own material." + map
  shows syllabus topics unlit.
- No syllabus: map regions from COR subjects only; exam banner hidden.
- Nothing due: deck shows "all caught up", stack at 2 layers, session start offers "Study anyway".
- Generation failed: job bar "…failed to generate" + Try again.

## Accessibility & motion
- The study map has an equivalent list (`accessibilityRepresentation`): subject → topic → mastery,
  exam days.
- Every quiz action has a key; focus moves to the next control after an answer.
- Reduce Motion: no flip (swap faces), no pop/shake, no stack lift, bars static.

## 3D
Opening a deck plays `DeckFan` (token `fan`): the due cards fan out in 3D, fan width = due count, then the first card deals to center.

## Acceptance criteria
- [ ] A deck with 23 due fans visibly wider than one with 7; Reduce Motion shows the first card directly. Evidence: `DepthMathTests` + screenshots.
- [ ] `StudyTests`: `Mastery.of`, `DueForecast.next7`, `GapSuggestion.make`, `ExamLink.decks`,
      `StudyMap.layout` (tile count, tower height monotonic in days), weak list ordering.
- [ ] Each of the 5 modes works with keyboard only. Evidence: manual.
- [ ] Recap shows the real next due dates written by FSRS. Evidence: test on the session reducer.
- [ ] Mark done persists across relaunch via `completedOverride`. Evidence: test.
- [ ] All existing generate / review / regenerate behaviour intact. Evidence: existing tests +
      manual.

## Seams
`QuizStore` (decks, `recordReview`), `FSRSAdapter`, `StudyStats`, `GenerationCenter`
(start/cancel/dismiss), `CardGenerator`, `AnswerExplainer`, `SyllabusStore` (items,
`completedOverride`, grading components), `SyllabusExtractor`, `CalendarBridge.exportSyllabusDeadlines`.
Backend fixes W6 (store data loss, import duplication) must land before this ships.

## Out of scope
Multiplayer, leaderboards, XP economy beyond the streak.
