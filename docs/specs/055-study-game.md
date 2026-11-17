# 055 Study session as a game

**Status:** shipped (2026-11-17)

## What changes for the student

Reviewing cards plays like a small card game. The card is dealt from a pile, tilts toward your finger and flips. Right answers build a combo that multiplies your points, quick answers heat the table, and LAR cheers you on. A missed card comes back later. The session ends with a score, your best, and the list of cards.

## Direction and references

- The owner, 2026-11-17: "plan a better UI for the quiz… game-like… gizmo-like… a Balatro effect… make learning more fun".
- Research (agy, 2026-11-17): Gizmo's quiz loop, Duolingo-style answer tiles and results tallies (Mobbin), and the "juice" techniques behind Balatro: tilt, sway, deal and flip, a score that bumps, small screen shake, a dithered swirl, pixel bursts, rising pitch. We take the feel, never Balatro's look: no chips, jokers, suits, its palette, its CRT or its font. The swirl is the portal's own, in its own ramp.
- Picks page: `reference/prototypes/quiz.html` (built from `quiz.src.html` and `quiz/*.html`). The owner picked one version per direction and asked for them built together:
  - **Deck B, "Card on calm":** the room's calm ground. The dithered swirl lives only on the card backs, the pile and the score panel.
  - **Run A, "Companion":** a stepped progress bar, a combo stamp and meter, LAR at the top saying a short line after each answer, answer tiles that press in, results in two steps.
  - **Heat B, "Heat by the clock":** a soft clock per card. A quick answer heats the table and earns a bonus. Running out is never a miss.
- Settled with the plan (the owner took the recommendations): the celebration lives inside the session only; no lives or hearts; all three modes; offline only, so no leagues or multiplayer, and a personal best per deck instead.

## Keep

- Spec 040 C9: the all-due session, oldest due first; one deck's due cards, or every card as practice when none is due.
- FSRS scheduling. Flash takes the student's rating; typed and choice answers rate themselves (right is Good, wrong is Again). Practice never changes the schedule.
- The intervals under each rating (#268). Why? (Ask LAR) after a miss, when IntAssis is installed.
- The 44 px minimum for every control (040 C7).

## Behaviour

- **C1. One table for every mode.** Flash, Type and Choice share the HUD, the card, the score and the results.
- **C2. HUD.** A stepped bar with one segment per card: gold when right, striped when missed. A missed card's return adds a segment outlined in the miss colour. Under it, the score panel over the swirl: the combo stamp (x1–x4, Pixelify), a meter toward the next tier with "x3 in 2", the soft clock ring, four heat cells and the score in pixel numerals. LAR stands under it with his line in a bubble. LAR's floating crystal steps aside while a session is open.
- **C3. Combo.** x2 at three right in a row, x3 at six, x4 at ten. A right answer scores 10 × the multiplier. Reaching a tier pops the stamp and gives LAR a line.
- **C4. Hard and Again.** Hard keeps the combo and scores nothing. A miss (Again, a wrong pick, a wrong typed answer) drops the combo and the heat to zero.
- **C5. A miss comes back.** The card shakes. A flashcard rated Again tucks back under the pile on its own. Typed and choice answers show the right answer, Why?, and Next. The card returns once, three cards later (or last). Its return is practice: only a card's first answer is scheduled.
- **C6. The soft clock (Heat B).** Each card gets 8 s (14 s to type) from when it lands. Answering right in the first half adds 5 points and heats the table one step (to at most 3). Answering after the clock cools it one step. Running out never counts as a miss. Time with the app in the background does not count.
- **C7. Heat.** Each heat step speeds the swirl and lifts it a tone, and the card's idle sway grows.
- **C8. The card (Deck B).** It is dealt face-down from the pile with a small overshoot and turns face-up as it lands. It sways a little at rest and tilts toward the finger, up to 8°. A flashcard flips for real. A right answer sends it off to the right with a pixel burst; a miss tucks it back toward the pile.
- **C9. The swirl.** One dithered portal swirl (4×4 Bayer, the portal's five-tone ramp) is drawn at low resolution and shared by the score panel, the card's back and the pile. At most 30 frames a second; nothing is drawn while the app is hidden.
- **C10. Sound.** With sound on (045 C19), each right answer plays a note one semitone higher per answer in a row, a tier plays a short rising run, and a miss is the low thump. No buzzer.
- **C11. Celebration lives here.** The session has its own kit: the stamp, the bursts, the small shake on a tier, and LAR's lines. It does not use the app's Confetti (045 C17 still holds everywhere else).
- **C12. Results, step one.** LAR, the deck's name, the points counting up in pixel numerals, then: best combo, accuracy, right first try, and the personal best. Hard counts as remembered in accuracy and first try, as it does for FSRS. "New best" stamps when a real (not practice) run beats an earlier best. The FSRS line from before stays.
- **C13. Results, step two.** "See the cards" lists every card with its rating and next review, misses first, filtered by All, Missed and Right. A miss has Why? (when IntAssis is installed). "Practice misses (N)" replays only the misses as practice; the other button goes back.
- **C14. Personal best.** Kept per deck on the phone (`studyBest:<deck id>`, or `all` for the all-due session). Practice never sets it.

- **C15. Any screen.** The session fills the page's column from a 320 px phone to a desktop window, with no sideways scroll. On short screens (760 px tall or less) the rows tighten, LAR steps down a size, the card gets shorter, and the page scrolls once so the score panel is at the top: the card and its answers then sit above the class bar and the tabs. Each swirl canvas shows a crop of one shared swirl at the same pixel size, so no shape stretches as the width changes.

## Copy

- LAR: "Tara, simulan natin!", "Tama!", "Galing!", "Sige pa!", "Ayos!", "Bilis mo!", "Okay, dahan-dahan.", "Tatlo na!", "Anim na!", "Sampu na!", "Balikan natin 'to.", "Isipin mo muna…", "Huling isa!", "Bagong rekord!", "Ang galing mo!", "Balikan natin ang mali."
- HUD: "x2 in 3", "Max combo". Card labels: "Term", "Type the term", "Pick the meaning", "Tap to show the meaning". Type miss: "It's {term}."
- Results: "pts", "New best", "Best combo", "x2 · 3 in a row", "Accuracy", "Right first try", "Personal best", "Previous best", "See the cards", "All", "Missed", "Right", "Nothing missed. A clean run.", "Practice misses (N)", "No misses to practice", "Back to Study", "Back to the deck".

## Data shape

- `src/lib/study/game.ts`: `Run`, `play()`, `mult()`, `toNext()`, `requeue()`, `clockSecs()`, `readBest()`/`saveBest()`. Pure and tested.
- `src/lib/study/fx.ts`: the shared swirl (`swirl` action, `table.heat`) and `bursts()`.
- `src/lib/sound.ts`: `sfx.right(step)`, `sfx.tier(step)`, `sfx.miss()`.
- No store or Rust changes.

## Errors

- A review that fails to save shows the existing friendly line under the card, and the card stays so it can be answered again. Nothing is scored.
- If the core cannot pick choice options, three other meanings from the deck are used. A typed check that fails shows the same line, and the student can check again.

## Motion and Reduce Motion

- Deal: `--t-hero` with a spring. Leave: `--t-move`. Flip: `--t-hero` with `--ease-spring`. Shake on a miss: `--t-hero`. Stamp pop: `--t-move`. Score count: eased each frame. Tier shake: trauma squared, decaying in about 0.6 s, only with effects on Full.
- Haptics: tick on right, press on a tier, fail on a miss, done at the end.
- You › Done effects (`app.effects`): Calm keeps the motion with fewer bits and no shake. Off, or Reduce Motion: no deal, tilt, sway, shake or bursts; cards fade; the swirl shows one still frame; the score jumps to its value.

## Accessibility

- The HUD's stamp, heat and score carry labels; the bar is a progressbar with its value. LAR's line is a polite live region.
- Every control is at least 44 px. Answers and terms are never in Pixelify.

## Tests

| Criteria | Test |
|---|---|
| C3, C4, C6, C5 | `src/lib/study/game.test.ts` |
| C11 | `tokens.test.ts` `c17_study_session_uses_its_own_kit` |
| C2, C8, C12, C13 | browser demo run (`INTPORTAL_WEB=1 vite dev`): flash, choice and type passes |
