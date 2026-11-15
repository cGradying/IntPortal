# 049 Intro

**Status:** building

## What changes for the student

A student opening IntPortal for the first time pages through the app before any form: one feature a page, each one something they can touch, while the portal and LAR answer on the stage above. Along the way they tell LAR their name, pick their campus, a look and reminders, so the app is theirs before they sign in.

## Direction and references

The owner, on a static storyboard (2026-11-15): "work more on it, make it more interactable and add animations". It replaces the three-tab welcome tour of spec 010 C45. The world is the landing's own (DESIGN.md): the night ground and stars, the tile portal, LAR, one gold for the one action, Pixelify only for one- or two-word labels and LAR's name.

## Keep

- The tile portal, its build, the carousel and the portal wall (010 C13a).
- The peek through the portal (010 C36–C37), the dither it opens with, and LAR's flight, bubble and carry (010 C18, C36, C41).
- The six dark looks and `setRoom`, worn by the whole landing (010 C45).
- The sign-in form, its fine print and the demo (011, 010 C39).
- Step through and the dive for a signed-in student.

## Behaviour

- **C1. Nine pages, in order.** Hello, Your school, Today, Deadlines, Grades and Study, Offline and private, Your look, Reminders, Sign in. The data lives in `src/lib/welcome/intro.ts`.
- **C2. Getting around.** Every page but the last has a gold Next (Reminders: Allow reminders until answered). Back sits at the top left on every page after the first, Skip to sign in at the top right on every page before the last. Nine short pixel bars between them show where the student is (gold for here, brighter for done). A long, flat horizontal swipe on the page turns it; a swipe on the campus row or the clock slider stays theirs. Android's Back turns back one page; a sheet over the form closes first.
- **C3. Nothing jumps.** Every page shares one cell, so the tallest sets the dock's height, and the row under the portal keeps its height through the intro: the portal is the same size on all nine pages, sign-in included. A page's content sits together just above Next.
- **C4. What is kept.** `src/lib/profile.ts` keeps the name under `intportal.name` (one-spaced, trimmed, at most 20 characters, empty removes it) and the campus under `intportal.campus`: a campus `name` exactly as in `crates/intportal-core/src/campus.rs`, or `school:<portal id>` for another school. Storage that throws is ignored. Other parts read these keys directly.
- **C5. The campuses.** The 25 PUP campuses are a TS list mirrored from `campus.rs`, in its order; a test fails if they drift.
- **C6. One motion per page turn.** The portal rings out from its centre, LAR flies to the page's spot (beside or under the portal, never on it) on his own wander code and says the page's line, and the copy rises in from the side it came from, title then line then the demo then Next, a beat apart. The page that leaves slips out the other way in 0.16 s. LAR never re-spawns and nothing that has arrived rises again.
- **C7. Each page does its thing on the stage.** Hello: LAR answers and hops. School: the portal rings, or the wall opens. Today: the portal's mouth opens onto a live view and holds while the page is up. Look: the whole landing wears it. Reminders: the phone is asked. Sign in: Look around first opens the demo.
- **C8. Hello.** The portal builds, LAR comes through and greets. "What should I call you?" (optional, 20 characters). As the student types, LAR types "Hi, Jan! Ako si LAR." in his bubble and hops and waves, once the typing pauses. The name then replaces "iskolar" in LAR's landing lines and page lines, and the launch hello says "Good morning, Jan." (010 C35).
- **C9. Today.** Inside the portal's mouth: Up next, COMP 20073, a countdown in pixel numerals and a bar through the class. A clock slider (6:45 to 9:15 AM, the class's stretch lit on the track) moves the sample time; crossing 7:30 turns Up next into In session with a haptic tick, crossing 9:00 into Done. The countdown ticks every second while the page is up and the app is on screen.
- **C10. Deadlines.** One sample row, Lab report 3. Ticking it plays the app's Done: the box fills, the title is struck, the DONE stamp lands; then the row folds away and "All clear" offers Put it back. No sparks, no burst.
- **C11. Grades and Study.** The GPA line draws itself across four sample terms, over faint 1.00, 1.50 and 2.00 guides, with the latest GPA in pixel numerals. A study card flips on a tap; Again, Good and Easy show when it comes back (`interval.ts`: 10m, 3d, 8d), and a rating says "Comes back in 3 days."
- **C12. Offline and private.** A No signal switch: the signal bars drop out one by one, and Schedule, Grades and Notes stay lit with a check, "Still open, from this phone." One sentence on the keychain and no server.
- **C13. Your look.** The six dark looks; a tap wears it on the whole landing at once, keeps it for the app, and LAR says so.
- **C14. Reminders.** A sample nudge sits in the page. Allow reminders asks the phone (`allowReminders` in `state.svelte.ts`, then `scheduleReminders(true)`), and the sample slides down from the top as the phone would show it, with the student's name, then slides away. Not now sets the reminder lead to 0, as FirstRun did, and turns the page.
- **C15. Sign in.** The form as before (011), with the school plaque and Peek inside back under the portal and "Look around first" in its fine print.
- **C16. After sign-in.** FirstRun keeps only the AI choice, and never shows on a build without AI (`chatModel()` empty). Who LAR is, where the data lives and reminders moved into the intro.
- **C17. Who sees it.** A student who is signed in, or who has reached the form or looked around once (`intportal.welcomed`), skips the intro and opens on the form or Step through, as before.

## Copy

| Page | Title | Line | LAR on arrival |
|---|---|---|---|
| Hello | Student IntPortal | Your PUP schedule, grades and deadlines, on your phone. | (his greeting) |
| School | Where do you study? | Pick your campus, so LAR knows your school. | Saan ka, {you}? Pili ka lang. |
| Today | Your next class, counting down | Drag the clock and watch Up next turn into In session. | Silipin mo sa portal. |
| Deadlines | Tick it off | Every due date in one list, with a heads-up before it. | Subukan mo, i-tick mo. |
| Study | Grades and study | GPA by term, and cards that come back on time. | Tap the card, {you}. |
| Offline | Works with no signal | Your login stays in the phone's keychain. No IntPortal server: the app talks only to PUP SIS. | Kahit sa jeep, walang problema. |
| Look | Make it yours | Pick a look. The whole app wears it. | Ano'ng bagay sa'yo? |
| Reminders | A heads-up before class? | A nudge 10 minutes before each class, and the evening before a deadline. Change it any time on You. | Ako na ang bahala sa paalala. |
| Sign in | (the form) | | Tara, {you}. Sign in na. |

{you} is the name, or "iskolar". Other lines: "Optional. It stays on this phone.", "PUP {campus}! Kilala ko 'yan.", "Ayos! Tapos na 'yan.", "Walang signal? Bukas pa rin lahat.", "Reminders are on. They start after you sign in.", "Your phone said no. You can allow them later in Settings.", the sample nudge "COMP 20073 in 10 minutes / S512, Data Structures. Tara na, Jan!".

## Data shape

- `src/lib/profile.ts`: `NAME_KEY`, `CAMPUS_KEY`, `CAMPUSES`, `cleanName`, `getName/setName`, `getCampus/setCampus`.
- `src/lib/welcome/intro.ts`: `PAGES` (`id`, `title`, `line`, `lar`, `spot`, `acts`), `SIGNIN`, `step`, `swipe`, `fillName`, `helloLine`, `campusLine`, the Today sample (`CLASS`, `CLOCK`, `todayAt`, `countdown`, `clock`), `TERMS`, `RATINGS`, `LOOKS`, `showFirstRun`.
- `PortalStage`: new `mouth` snippet prop and `steady` prop; new `ring()`, `visit(spot)`, `cheer()`. `LarFlight`: `visit`, `cheer`. `PortalPeek`: `view` snippet.

## Errors

- No notification engine (a browser) or the phone says no: the sample still slides down; the page says how to allow them later.
- The portal fails to load: the pages and the form still work; the Today view has no mouth to open into.
- Storage off: nothing is kept, and the intro shows again next launch.

## Motion and Reduce Motion

Page turn: arrive 0.55 s (`--t-hero`) with 40 ms between title, line, demo and Next; depart 0.16 s. The GPA line draws over 1.1 s. The nudge slides 0.55 s. Haptics: select on a turn and a pick, tick when the class phase changes and on a rating, done on a tick-off and on Allow. Reduce Motion: no slides and no flight; pages swap in place (the app's global rule ends every animation at once), LAR is simply at his spot, the card turns without the flip, the nudge fades. Nothing ticks or animates while the app is hidden.

## Accessibility

Every control is 44 pt or more. The bars read "Step 3 of 9: Your next class, counting down". Hidden pages are inert. The campuses are a radio group, the looks and the other school are toggle buttons, No signal is a switch, the slider speaks its time, the Today view and the rating are live regions, and LAR's lines reach VoiceOver as before.

## Out of scope

The campus's own colours (W4's campus work reads `intportal.campus`); a light look on the landing; an AI page before sign-in.

## Test map

| Criterion | Check |
|---|---|
| C1, C2, C6, C7, C8, C9, C11, C13, C16 | vitest `welcome/intro.test.ts` |
| C4, C5 | vitest `profile.test.ts` (keys, cleaning, throwing storage, parity with `campus.rs`) |
| C8 | vitest `lar/lines.test.ts` (name for iskolar), `greeting.test.ts` |
| C3 | browser at 390 by 844 and 375 by 667: the canvas is the same height on all nine pages |
| C6, C9, C10, C12, C14 | recording on the phone |
| C17 | review: `intro` is `!returning && !seen` in `Landing.svelte` |

## Open questions

None.
