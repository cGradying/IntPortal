# 049 Intro: a talk with LAR

**Status:** shipped (0.3.0, #295). Every criterion is built; the feel on a real iPhone is the owner's to confirm.

## What changes for the student

A student opening IntPortal for the first time meets LAR on a page of its own, before the portal and before any form. It reads like a messaging thread: LAR sits large at the top, his lines type themselves out under him, and the student answers with the chips at the bottom. Along the way they tell LAR their name, their campus and what they care about most, try the app's main moves on small live cards, pick a look and reminders, and hear in one exchange where their login is kept. Then LAR says "Tara, pasok na tayo", and the portal builds where he stood, with the sign-in form under it.

## Direction and references

The owner, on the nine-page intro that ran on the portal stage (2026-11-16): "for the landing page make its own page to talk with the person, not just in the portal." It replaces those nine pages (this spec's first version) and, before them, the three-tab welcome tour of spec 010 C45. The world is the landing's own (DESIGN.md): the night ground and stars, LAR, one gold for the one action, Pixelify only for LAR's name and one- or two-word labels. The portal stage is now only the door: sign-in, the portal wall and the peek.

## Keep

- The tile portal, its build, the carousel, the portal wall and the peek (010), untouched.
- LAR's slab, typed text and caret from his landing bubble (`LarFlight`), now as lines in a thread.
- The six dark looks and `setRoom`, worn live.
- The sign-in form, its fine print and the demo (011, 010 C39). "Look around first" stays in the fine print.
- Step through and the dive for a signed-in student.

## Behaviour

- **C1. One conversation, as data.** `src/lib/welcome/intro.ts` holds every step: what LAR says, how the student answers, what each answer makes LAR say and do, and where it leads. The order is name, campus, what matters, the four demos, offline, look, reminders, privacy, and "pasok na tayo". `play(answers)` returns the whole thread for the answers given so far.
- **C2. Getting around.** Back, at the top left, takes the last answer away (Android's Back does the same); the thread before it stays exactly as it was, and nothing that has arrived rises again. "Skip to sign in", at the top right, goes straight to the portal and its form. A tap on the thread while LAR types finishes his lines at once.
- **C3. One gold at a time.** Each step shows at most one gold action; other answers are quiet chips. A campus is its own answer, so that step has no gold.
- **C4. What is kept.** `src/lib/profile.ts` keeps the name under `intportal.name` (one-spaced, trimmed, at most 20 characters, empty removes it); the campus under `intportal.campus` (a campus `name` exactly as in `crates/intportal-core/src/campus.rs`, or `school:<portal id>` for another school); and what they care about under `intportal.focus`, their picks from `classes`, `deadlines`, `grades` and `study`, comma-joined in the order picked. Storage that throws is ignored. Other parts read these keys directly. Nothing else reads `intportal.focus` yet: the order of Today's cards is the next thing that should.
- **C5. The name.** LAR opens: "Uy! Ako si LAR, galing sa kabilang side ng portal." then "Bago tayo pumasok: what should I call you?". A text field (20 characters) with a gold Send, or the chip "Iskolar na lang". He answers by name, "Hi, Jan! Tanda ko na 'yan.", and uses it from then on; without one he says "iskolar". The name also replaces "iskolar" in LAR's landing lines and the launch hello (010 C35).
- **C6. The campus.** The 25 PUP campuses (a TS list mirrored from `campus.rs`, in its order; a test fails if they drift) in two rows that scroll sideways. A tap is the answer: "PUP Sta. Mesa! Kilala ko 'yan." "Another school", shown when the core lists more than one portal, is answered "Sige! Pipili tayo sa portal wall pagdating doon."; the wall then opens by itself once the portal stands, and the school picked there is kept as `school:<portal id>`.
- **C7. What matters.** Classes, Deadlines, Grades, Studying: any number, as toggles, then gold "'Yan na" (or "Lahat" with none picked). The demos that follow come in that order, the picked ones first as picked, then the rest.
- **C8. The demos, in the thread.** Each is one line from LAR, a small live card under it, and one gold chip to go on. The cards are components in `src/lib/welcome/`:
  - Classes (`ClockCard`): Up next, COMP 20073, a countdown in pixel numerals and a bar through the class. A clock slider (6:45 to 9:15 AM, the class's stretch lit on the track) moves the sample time; crossing 7:30 turns Up next into In session with a haptic tick, crossing 9:00 into Done. It ticks every second while it is the step on screen and the app is visible.
  - Deadlines (`DueRow`): one sample row, Lab report 3. Ticking it plays the app's Done: the box fills, the title is struck, the DONE stamp lands; then the row folds away and "All clear" offers Put it back. No sparks, no burst.
  - Grades (`GpaCard`): the GPA line draws itself across four sample terms, over faint guides, with the latest GPA in pixel numerals.
  - Studying (`FlashCard`): a card flips on a tap; Again, Good and Easy show when it comes back (`interval.ts`: 10m, 3d, 8d), and a rating says "Comes back in 3 days."
  - Offline (`SignalCard`), always shown after the four: a No signal switch. The bars drop out one by one, and Schedule, Grades and Notes stay lit, "Still open, from this phone."
  A card that is no longer the step asking steps back (dimmed, inert).
- **C9. The look.** The six dark looks as toggles; a tap wears it on the whole page at once and keeps it for the app. Gold "Ito na" answers with the look's name.
- **C10. Reminders.** A sample nudge sits in the thread (`Nudge`). "Allow reminders" asks the phone (`allowReminders` in `state.svelte.ts`), and the sample slides down from the top as the phone would show it, with the student's name, then slides away. "Not now" sets the reminder lead to 0, as FirstRun did.
- **C11. Privacy, in one exchange.** "Last na. Ang login mo, sa phone mo lang: nasa keychain, at PUP SIS lang ang kinakausap ko." Gold "Got it" goes on; "Paano?" gets two more lines (he signs in for you as a browser would, no IntPortal account or server, then it works offline) and its own "Got it".
- **C12. LAR reacts.** He comes out of his fire as the page opens. An answer he likes (a name, a campus, the picks, a look, reminders) gets his hop and wave; a plain "next" gets a thumbs-up; "Paano?" makes him think. Finishing a demo (a tick, a rating, No signal, the class starting) gets the hop too.
- **C13. The handoff.** After "Tara, {you}, pasok na tayo!" the thread, the bar and the stars fade and LAR goes back into his fire. Then the landing's clock starts afresh: the portal builds in the room he left, he comes out under it, and the form rises (010 C16). Nothing from the talk is still on screen and nothing rises twice. Skip does the same without the last line.
- **C14. After sign-in.** FirstRun keeps only the AI choice, and never shows on a build without AI (`chatModel()` empty).
- **C15. Who sees it.** A student who is signed in, or who has finished or skipped the talk or looked around once (`intportal.welcomed`), never sees it: they open on the form or Step through, as before.

## Copy

LAR speaks short Taglish, in the voice of `lar/lines.ts`; the student's chips are short English or Taglish. Every line is in `intro.ts`, and a test keeps each under 110 characters with the longest name.

| Step | LAR | The student |
|---|---|---|
| Name | Uy! Ako si LAR, galing sa kabilang side ng portal. / Bago tayo pumasok: what should I call you? | (a name) Send, or Iskolar na lang |
| Campus | Saan ka nag-aaral, {you}? | (a campus), or Another school |
| What matters | Ano'ng pinaka-kailangan mo araw-araw? Pili ka, kahit ilan. | Classes, Deadlines, Grades, Studying; 'Yan na or Lahat |
| Classes | Ganito ko ipapakita ang next class mo. I-drag mo ang oras. | Ayos |
| Deadlines | Lahat ng due mo, isang listahan. Subukan mo, i-tick mo. | Tapos! |
| Grades | GPA mo kada term, isang linya. Sample lang 'to, ha. | Nice |
| Studying | May flashcards din. I-tap mo ang card, tapos i-rate mo. | Gets |
| Offline | Walang signal sa jeep? I-on mo 'to, tingnan mo. | Solid |
| Look | Ano'ng bagay sa'yo, {you}? Isuot mo. | (six looks) Ito na |
| Reminders | Paalalahanan kita 10 minutes bago bawat klase, at gabi bago ang deadline? | Allow reminders, or Not now |
| Privacy | Last na. Ang login mo, sa phone mo lang: nasa keychain, at PUP SIS lang ang kinakausap ko. | Got it, or Paano? |
| Go | Tara, {you}, pasok na tayo! | |

His answers: "Hi, {you}! Tanda ko na 'yan.", "Sige, iskolar na lang muna.", "PUP {campus}! Kilala ko 'yan.", "Sige, 'yan ang uunahin ko.", "Lahat? Sige, isa-isahin natin.", "Ayan, bagay. Ganyan na ang kulay ng app mo.", "Ayos! Magsisimula 'yan pag naka-sign in ka na.", "Sige. Nasa You tab lang 'yan pag gusto mo na.". Under the name field: "Optional. It stays on this phone." The sample nudge: "COMP 20073 in 10 minutes / S512, Data Structures. Tara na, Jan!".

## Data shape

- `src/lib/profile.ts`: `NAME_KEY`, `CAMPUS_KEY`, `FOCUS_KEY`, `CAMPUSES`, `FOCI`, `Focus`, `cleanName`, `cleanFocus`, `getName/setName`, `getCampus/setCampus`, `getFocus/setFocus`.
- `src/lib/welcome/intro.ts`: `STEPS` (a `Step` is `id`, `lar`, `card?`, `ask`, `replies`; a `Reply` is `id`, `label`, `gold?`, `says`, `act?`, `to?`), `FOCUS`, `route(focus)`, `Answer` (`reply`, `value?`), `Item` (LAR's line, the student's line, or a card), `play(answers)` returning `Thread` (`items`, `step`, `done`, `act`, `name`, `campus`, `focus`, `wall`), `fill`; the samples (`CLASS`, `CLOCK`, `todayAt`, `countdown`, `clock`, `TERMS`, `RATINGS`), `LOOKS`, `isDarkLook`, `showFirstRun`.
- `src/lib/welcome/Talk.svelte` draws the thread and runs the acts (`cheer`, `think`, `wall`, `remind`, `quiet`); `Landing.svelte` shows it for a new student and takes `onend({ wall })`.

## Errors

- No notification engine (a browser) or the phone says no: the sample still slides down, and under the sample in the thread it says "Your phone said no. You can allow them later in Settings."
- The core lists only one portal: "Another school" is not offered.
- Storage off: nothing is kept, and the talk shows again next launch.
- The portal fails to load: the talk is unaffected; the form still works after it.

## Motion and Reduce Motion

One language, on the shared vocabulary (`motion.ts`, 045 C30–C36). LAR's side grows: a slab or a card steps out of its top-left corner in four frames (0.2 s, pixel art, so stepped), then the line types at 42 characters a second behind a gold caret, in a slab that already has its full size. The student's side rises: their line and each new reply set fade up (`rise`). The thread scrolls itself to the newest line, and eases down when a shorter reply set leaves room (`--t-move`). The handoff fades out on `--t-exit` and `--ease-in` while LAR's fire takes him over 0.65 s. Everything is transform and opacity. Haptics: select on an answer and a pick, tick when the class phase changes and on a rating, done on a tick-off and on Allow. Reduce Motion: every line is simply there, whole; the student's lines and the replies only fade; LAR stands still; the handoff is a cut. Nothing types, ticks or twinkles while the app is hidden.

## Accessibility

The thread is a log, announced politely: each of LAR's lines reaches VoiceOver once, whole, as "LAR: …" (the typed copy is hidden from it), and the student's as "You: …". Each new reply set takes the focus, as a group named "Your reply". Every control is 44 pt or more. The campuses are buttons in a named group, the picks and the looks are toggle buttons, No signal is a switch, the slider speaks its time, and the class view and the rating are live regions. Cards that are no longer the step asking are inert.

## Out of scope

Reordering Today's cards from `intportal.focus`; the campus's own colours; a light look on the landing; resuming a half-finished talk after the app is closed; an AI page before sign-in. `PortalStage` still carries the old intro's `mouth`, `steady`, `visit` and `cheer`, now unused; they go in a follow-up.

## Test map

| Criterion | Check |
|---|---|
| C1, C2, C3, C5, C6, C7, C8, C9, C10, C11, C14 | vitest `welcome/intro.test.ts` |
| C4, C6 | vitest `profile.test.ts` (keys, cleaning, the focus order, throwing storage, parity with `campus.rs`) |
| C5 | vitest `lar/lines.test.ts` (name for iskolar), `greeting.test.ts` |
| C2, C8, C12, C13 | browser at 375 by 667, 390 by 844 and 440 by 956, the whole talk walked; a recording on the phone |
| C15 | review: `talking` starts as `!returning && !seen` in `Landing.svelte`; browser: a second launch opens on the form |

## Open questions

None.
