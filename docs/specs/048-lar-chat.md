# 048 LAR's chat, round four

**Status:** shipped (2026-11-14, #248–#251). Approved 2026-11-10. The owner left the design calls to the round-four page, then picked from it: opening A, Pour; the sky header at one fixed size with LAR the same size throughout; LAR's steps as a pixel trace. Mockup: `reference/prototypes/lar-chat.src.html` (rows `morph`, `chat`), live at https://claude.ai/artifact/NFGHK9EaGWYGcUim2PuyCU.

## What changes for the student

Tapping the crystal dithers LAR's chat open out of it, a pixel wave. The chat has a clear header again: a sky band with LAR standing on it, his name, what he is doing, New chat and Close. While he works, the student sees what he really did (read the timetable, searched the notes and what he found, wrote), folded into one line once he answers. Suggestions sit in one row over the input and follow the day and each answer.

## Direction and references

- Owner, 2026-11-10: "the old one where it has a clear and smooth header"; the cube expanding should be "like changing its atom form"; the header should have "a split like from the previous spec" and be premium; LAR's link to notes "doesn't look good", make it minimal, pixel, 2.5D; LAR "too small" and "not aligned"; then "make sure it doesn't resize, same size even if it fills up the chat, LAR stays the same size too".
- The header is the old sheet's sky stage (`AssisSheet.svelte` before c193d46: `.stage`, `.sky`), inside the glass.
- Opening: the container itself becomes the destination (Material's container transform); one continuous motion along curved paths, no stops (Dynamic Island). Four other openings were mocked and not picked: Layers, Turn, Dither, and two Pour-and-dither blends.
- Replaces round three's in-window details: LAR by the input, the thin top row, the front-face growth (046 C1d) and the neuron canvas (046 C1d3).

## Keep

- The floating glass window anchored on the chip's corner, growing up with the chat to at most 60% of the screen, resting on the keyboard when it is up (round three; `AssisWindow.svelte`).
- The chip is the same button and WebGL canvas; there is never a second WebGL context.
- Messages, proposals and confirm cards, card editing, From chips, Stop, history, LAR's moods, his spawn and fold, the dozing minute, haptics.
- The low-RAM tier (046 C1d2) and every Reduce Motion fallback.

## Behaviour

**Opening and closing: Dither**

- **C1.** Tapping the chip starts a Bayer dither: the chip hides and one 2D canvas over the page paints the window's face (C3) through a grid of square 6 pt cells on the device-pixel grid, crisp, no smoothing. A cell is shown when its 4×4 Bayer threshold is below the reveal minus its scaled distance from the chip's centre, so the window materialises out of the chip as a pixel wave. It runs 420 ms, eased and in steps. (3D pour replaced by a pixel dither at the owner's request, 2026-11-14.)
- **C2.** The cells nearest the chip show first and the farthest last; at reveal 0 nothing shows, at 1 every cell does. There is no cube turn and no flying tile.
- **C3.** The face is drawn once offscreen in window coordinates: the glass, the sky band of the header's height (C7) over it, the lit top, the dithered edge, the gold rim and the 2 pt extrusion. The last frame is the window exactly, and the real window replaces the canvas in one frame, with no cross-fade.
- **C4.** After the swap, the sky's light and stars come up, LAR spawns on the horizon, his hello types in, and the suggestions appear.
- **C5.** The window lands at its measured first-open height (header, hello, suggestions and dock), not a fixed one. After that it grows with the chat, as it does now.
- **C6.** Closing: LAR folds into his fire (0.3 s). The window swaps to the canvas and the dither plays backwards in 320 ms, outer cells first, into the chip, which reappears as the last cells go. Reduce Motion cross-fades; a backgrounded app finishes at once.

**The header**

- **C7.** The header is one fixed size, 40 of LAR's sprite pixels tall (about 93 pt on an iPhone), and never folds: not with the keyboard up, not in a long chat. LAR is the same size throughout.
- **C8.** The sky is a solid band in the portal ramp (`--r0` to `--r4`): three slow pools of light (a 16 s drift), six 2 pt stars that twinkle in steps, and a 1 pt lit top edge. A two-row pixel dither, 6 pt tall, splits it from the glass below. The pools are one oversized pseudo-element layer whose drift is a `transform`, and the stars and the live pixel change only `opacity`, so nothing repaints per frame (no `background-position` animation). On the low-RAM tier (046 C1d2) the sky holds still, the stars stop and the live pixel stays lit while the model is waking or thinking (#189); it moves again once he is done.
- **C9.** LAR is drawn at about 2.4 pt a sprite pixel, rounded down so one sprite pixel is a whole number of screen pixels (7 on a 3x iPhone) and he stays sharp. His perch is the top of his sprite box down to his feet, 48 sprite pixels wide, and nothing clips him: his sleep Z, antenna and waving mitt stay inside the header, and his feet may stand a few points over the dither, drawn above the chat. The name, status and keys are centred vertically on him. (Owner, 2026-11-10: "make lar smaller… a little bit more compress… his assets doesnt suddenly vanish".)
- **C10.** "LAR" is in the pixel face at 16 pt, cream. The status line (12.5 pt) starts with a 6 pt live pixel: gold and still at rest, blinking while he works. The status reads what he is doing now (Copy).
- **C11.** New chat (shown only once there are messages) and Close are one pair: 36 pt pixel-cut keys, dark on the sky, with a lit top edge and a shaded bottom. Each has a 44 pt hit area, and both icons are drawn on the same 7×7 pixel grid at 2 pt a pixel.

**LAR's steps**

- **C12.** While LAR works, a trace of his real steps appears under the question, in order, and only the steps that happen:
  - "Waking up", only when the model has to load first.
  - "Read your timetable" ("Read your dues and timetable" for a due question).
  - For an open question: "Searching your notes and decks", which ends as one of these:
    - "Found …", named from the kinds of what it found (recall returns notes, decks as `card:` keys and subjects as `plan:` keys; `sources.ts`): "Found 2 notes", "Found 1 note and 1 deck", "Found 2 notes, 1 deck and 1 subject". Up to three chips follow, each with its kind's icon, then the first line it matched (two lines at most).
    - "Nothing close in your notes or decks".
    - "Note search is off".
  - "Writing", only while the model writes.

  A rule answer (due, classes, grades) never shows "Writing"; it may still show the search, which really runs for it. A request (remind, note, cards) is not searched, so it shows only the read step. No thoughts are made up.
- **C13.** The trace is pixel and 2.5D:
  - Each step is an 8 pt gold cube with a lit top and a shaded side. Running, it blinks; done, a cream datum pixel shows on it.
  - A 2 pt gold line joins the cubes, with a 1 pt shadow. It grows down in six steps, and a 2 pt packet runs down it to each new step.
  - A search that finds notes turns a square pixel corner out to the note chips.
- **C14.** When the answer arrives, the trace folds into one line: its cube, a summary, and a chevron. Tapping the line opens the trace again. Summaries: "Looked at" with the same kinds as the found line ("Looked at 2 notes", "Looked at 1 note and 1 deck"), "Read your dues", "Read your timetable", "Searched, nothing close".
- **C15.** Where an answer came from lights up in 8 pt pixel corner brackets for 1.4 s: its From chips, and its card on the page behind (`data-source`) when that card is on screen. Nothing is drawn outside the glass otherwise. The neuron canvas (046 C1d3) is removed.

**Suggestions**

- **C16.** Suggestions are one row over the input that scrolls sideways, with soft edges. There are at most four, each a 36 pt chip with a 44 pt hit area. They never stack up in the log.
- **C17.** Before the first message, they come from the student's day, each with a short gold reason. Each is skipped when its data is missing:
  - The nearest due: "What's due this week?" with the due's short title and day.
  - The last note opened: "Explain *title* simply", with the reason "last note".
  - The next class today: "Anong klase ko ngayon?" with its start time.
  - "Remind me bukas ng umaga", which fills the field.

  With a note open, the editor's starters lead, as now (020 C5).
- **C18.** After an answer in this session, the follow-ups come from its intent and sources, by rule, with no model call:
  - Due: "Remind me *day before* night" (fills the field), "Open *title*".
  - Classes: "What's due this week?", "Open *subject*".
  - An open answer with sources: "Make 5 cards from *first source*", "Open *first source*". (Named, not "from this": the card intent needs a topic.)
  - Anything else: the day's suggestions again.

**The glass**

- **C19.** The window's face is one glass gradient with a 1 pt lit top and left edge, a gold rim on the right and a 2 pt pixel extrusion to the lower right (2.5D). LAR's speech stays on its dark pixel-cut card.

## Copy

- Header: "LAR". Status: "On this phone", "Waking up…", "Reading your timetable…", "Searching your notes and decks…", "Writing", "Making cards", "Still waking up. This phone is slow.", "Dozing. Ask me anything."
- Steps: "Waking up" / "Woke up", "Read your timetable", "Read your dues and timetable", "Searching your notes and decks…", "Found " + the kinds list, "Nothing close in your notes or decks", "Note search is off", "Writing".
- Kinds list: counts in the order notes, decks, subjects, singular at 1 ("1 note", "2 decks", "1 subject"), joined with commas and a final "and": "2 notes", "1 note and 1 deck", "2 notes, 1 deck and 1 subject". Built by one pure function, `foundLine(sources)` in `apply.ts`.
- Folded trace: "Looked at " + the kinds list, "Read your dues", "Read your timetable", "Searched, nothing close".
- Keys: "New chat", "Close" (accessible names).
- Suggestions: as in C17 and C18.

## Data shape

- `src-tauri/src/ai.rs` `ai_ask` gains `on_step: Channel<Step>`. It sends `{ step: "read" }` before the facts, `{ step: "search" }` before recall, then `{ step: "found", found: Source[], quote: string }`, `{ step: "nothing" }` or `{ step: "search_off" }`, and `{ step: "write" }` when the model's first words arrive. `Ask` gains `intent: "ask" | "note" | "remind" | "cards" | "due" | "classes" | "grades"`, from `intent::resolve`. The quote is the first recalled line, trimmed to 140 characters.
- `src/lib/assis/assis.svelte.ts`: each LAR turn in `assis.chat` gains `steps: Step[]` and `intent`. The wake step comes from the app's own load (`busy === "waking"`). Steps and intent are session-only: the `turns` table (`store.rs`) is unchanged, so a turn restored from history shows its answer with no trace (history keeps only the text today), and the suggestions fall back to the day's (C17).
- `src/lib/assis/apply.ts`: `starters(day)` and `followUps(turn)`, both pure and tested.
- `src/lib/assis/dither.ts` (was `pour.ts`): the dither grid, timing and mask, pure; `dither-draw.ts` paints it. `chip.face` is gone (no cube turn).
- `src/lib/assis/neuron.ts` and its tests are removed.

## Errors

- Search fails: the step ends "Note search is off" and the answer comes from the schedule.
- The model fails or is stopped: the running step stops blinking, and the existing friendly error or "Okay, stopped." follows. The trace still folds.
- No WebGL (046 C1d2): the dither is 2D and runs the same.

## Motion and Reduce Motion

- Opening is 420 ms; closing is a 300 ms fold plus 320 ms of dither. Only the canvas and transforms move: no width, height or position is laid out per frame. The target is 60 fps, measured on the iPhone 18 Pro simulator and a real phone. The tick haptic fires as the window lands.
- The sky moves only on the compositor: the pools' layer by `transform`, the stars and the live pixel by `opacity`. It stops when the window is closed or the app is hidden, and on the low-RAM tier while the model wakes or thinks (C8). The mockup animates `background-position` for convenience; the app does not.
- Reduce Motion: a 200 ms cross-fade, with no turn, no atoms, no sky drift, no twinkle, no packets. The trace appears without growing, and the source corners show without fading.
- Low-RAM phones dither too: one 2D canvas for 0.42 s.

## Accessibility

- The dialog is still "Ask LAR"; focus goes to the dialog on open and back to the chip on close. The input takes focus only when tapped: a text field focused from code sets the app's keyboard state and hides the tab bar and dock, but iOS shows no keyboard for it, so the bottom of the page went blank behind the window (owner, 2026-11-10).
- The trace is a list named "What LAR did". The folded line is a button with `aria-expanded`. Each step's words are its accessible name; the cubes are hidden from VoiceOver. The log stays a polite live region announced once per reply.
- The keys and chips meet 44 pt hit areas. Cream on the sky ramp's darkest band meets 4.5:1, checked for each room.

## Out of scope

- The study cards flow, the Why? button and proposals (unchanged).
- Any change to how answers are made; only the step events and the intent are new.
- The editor's Ask AI bar (020).

## Test map

| Criterion | Check |
|---|---|
| C1–C6 | `vitest dither` (grid, empty at 0 and whole at 1, nearest first, the reverse); simulator recording, frames at 100, 200, 420 ms and close; frame times during open |
| C7–C11 | Simulator screenshots in Night and Day, keyboard down and up, in a long chat: the header keeps one height, and LAR's Z, antenna and wave are whole |
| C12–C15 | `cargo test` for `ai_ask` step order (read, search, found/nothing/off, write) with a stub model; `vitest apply` for `foundLine` (notes only, mixed kinds, singulars); `vitest assis` for steps on a live turn and none on a restored one; screenshots of each trace |
| C8 | Screenshot of the sky; on a small-RAM simulator run, the sky still while waking and thinking; the release gate's real-phone 60 fps includes the sky |
| C16–C18 | `vitest apply` for `starters` and `followUps` with fixtures |
| C19 | Screenshot |

## Open questions

None.
