# IntPortal UI revision, phase 2 plan

Phase 1 (PLAN.md) shipped the tokens, pixel components, depth kit, sidebar shell and portal landing, merged as PRs #18 to #24 on 2026-09-24.
Phase 2 rebuilds every screen on that foundation, one slice per PR, built by `sonnet` workers and reviewed by the head (Opus, main chat).
Students see each screen change from the old glass layout to the Registrar sheets in the approved prototype (`docs/specs/prototypes/intportal-v3.html`).
Every slice keeps its spec's "Current behaviour inventory". A slice that drops a behaviour fails review.
Today, Notebook, Quizzes and Syllabus all render through one 1,179-line `AgendaView` today. AG splits it first so four workers never edit the same file.
The operator merges every PR. The head never merges.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-stack.md`, with one change. Slices are independent PRs against `main`, not one linear stack, because the operator merges as they come.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] Arm a `/goal` with this exact text. "Run docs/specs/PLAN-2.md in IntPortal. Waves A, B, C in order. A PR is verified only when its unit, live, and perf boxes are all checked. Workers build, the head reviews, the operator merges. Done when every slice PR is open with a clean verdict."
- [ ] Read these from trunk at program start and at every tick.
  - [ ] `git show origin/main:DESIGN.md`
  - [ ] `git show origin/main:docs/specs/README.md`
  - [ ] `git show origin/main:docs/specs/PLAN-2.md`
- [ ] Arm the 30-minute audit tick as a `/loop` in this chat. Tick prompt, verbatim. "Re-read PLAN-2 from trunk and the armed /goal. Probe every active worker by its side effects (commits, test logs, snapshot files). Stand down a stuck worker and dispatch its replacement. Then post a status message to the operator with the table of slice, worker, state, head SHA and PR, what merged, and blockers."
- [ ] On the operator's hold, send every worker a zero-writes order at once.

### Spawn owners

- [ ] Each slice has one `sonnet` worker (`subagent_type: general-purpose`, model `sonnet`) in its own worktree at `../IntPortal-wt/<slice>`, on branch `ui/<slice>` from `origin/main`. The head builds AG itself.
- [ ] Run at most four workers at once. Sonnet hit its session limit twice in phase 1.
- [ ] Waves.
  - [ ] Wave A starts now with AG (head), C1, SC1, G, MB, ST1, HF.
  - [ ] Wave B runs SC2 after SC1. T1 after AG and ST1. T2 after AG. ST2 after AG and ST1. ST3 after ST1. ST4 after AG and ST1.
  - [ ] Wave C runs AS after T2. SE after C1 and #26 (W10). DOCS last.
- [ ] Hold the file boundaries. `Views/Shell/AppShell.swift` is shared. A slice edits only its own `case` line in `AppShell.screen(_:)`, and the head resolves any conflict there at merge.
- [ ] A dependency counts as met when its PR is merged, or when its branch has a clean verdict and the dependent branches from it.

### PR mechanics, for every PR

- [ ] Use `gh` against `cGradying/IntPortal`. Open the PR ready, never draft, with `gh pr create --base main`.
- [ ] Run `swift build` and `swift test` before the PR-facing push. Paste the `Executed N tests` line into the PR body.
- [ ] Commit messages follow the repo's `type(scope): subject` style and end with the Co-Authored-By line from the session attribution rule.
- [ ] Replace the old view in place and delete it in the same PR. No `V2` files, no feature flags.
- [ ] Numbers under 20pt use `Typography.numeric` (DESIGN.md, the Legibility Rule).
- [ ] Every animation reads a `Motion` token and the `\.reduceMotion` environment value.

### Verdict and merge, for every PR

- [ ] The head reviews the diff against the spec's inventory and acceptance boxes, reads every snapshot, and runs `swift test` at the PR head.
- [ ] One `sonnet` verifier agent runs the ten live lanes in sequence and returns the screenshot paths. The head reads every screenshot before the verdict.
- [ ] Clean only when every lane is `PASS`. Findings go back to the worker by `SendMessage`. A new head SHA gets a fresh verdict.
- [ ] The head posts the verdict, screenshots and PR link in chat. The operator merges.

### Boot recipe, for every live lane

- [ ] `git worktree add ../IntPortal-wt/lane-<slice> <head SHA>`.
- [ ] Snapshot lanes run `INTPORTAL_SNAPSHOT_DIR=/tmp/swarm-<slice>/ swift test --filter <Suite>`. Each slice adds a `<Slice>SnapshotTests` suite that renders its screen through `Snapshot.render` with demo data.
- [ ] Live lanes run `CONFIGURATION=Debug Scripts/make_mac_app.sh /tmp/lane-<slice>`, then `open /tmp/lane-<slice>/IntPortal.app --args -IntPortalDemo -IntPortalScreen <screen>` with `CFFIXED_USER_HOME` set to a temp dir. Input goes through `osascript` keystrokes only.
- [ ] Live screenshots use `Scripts/shot.sh`, which needs Screen Recording for the terminal. Until the operator grants it, a live lane records `BLOCKED: Screen Recording` and its snapshot twin stands in. The head reruns blocked lanes once it is granted.
- [ ] Save every screenshot to `/tmp/swarm-<slice>/<slug>.png`.

## Split AgendaView into four screens (AG)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Create `Views/Today/TodayScreen.swift`, `Views/Notebook/NotebookScreen.swift`, `Views/Quiz/QuizzesScreen.swift` and `Views/Syllabus/SyllabusScreen.swift`, moving code out of `Views/AgendaView.swift`.
- [ ] Edit `Views/Shell/AppShell.swift` so each destination has its own `case`.
- [ ] Delete `Views/AgendaView.swift` once it is empty, or leave only shared helpers under 200 lines.

**Build.**

- [ ] A behaviour-preserving move. No visual change. Shared state (`notebook.tab`, open note, Ask AI) stays on `AppState.notebook`.

**You see.**

- [ ] Every screen looks exactly as before. ⌘2, ⌘4, ⌘5 and ⌘6 still open Today, Notebook, Quizzes and Syllabus.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `swift test` passes with the same test count as `main`.
- [ ] `ShellTests` still pass. Run `swift test --filter ShellTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot Today on trunk and head. Save `today-trunk.png` and `today-head.png`. Pass when the images are identical.
- [ ] Lane 2. Same for Notebook. Save `notebook-head.png`. Pass when identical to trunk.
- [ ] Lane 3. Same for Quizzes. Save `quizzes-head.png`. Pass when identical to trunk.
- [ ] Lane 4. Same for Syllabus. Save `syllabus-head.png`. Pass when identical to trunk.
- [ ] Lane 5. Live, press ⌘2 ⌘4 ⌘5 ⌘6. Save `shortcuts.png`. Pass when each opens its screen.
- [ ] Lane 6. Live, open a note, switch to Quizzes and back. Save `note-kept.png`. Pass when the same note is still open.
- [ ] Lane 7. Live, select text and use Ask AI. Save `ask-ai.png`. Pass when the Ask AI menu appears.
- [ ] Lane 8. Live, start a deck generation, switch screens. Save `job-bar.png`. Pass when the job bar survives the switch.
- [ ] Lane 9. Run `wc -l` on the four new files. Save `sizes.png` of the output. Pass when none is over 500 lines.
- [ ] Lane 10. Run `grep -rn AgendaView Sources`. Save `grep.png`. Pass when nothing references the removed type.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Idle CPU on Today with the window active, Debug demo mode.
- [ ] Probe. `ps -o %cpu` sampled every second for 30 seconds, trunk then head, three runs each.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head median within 1 point of trunk.

**Review gate.** None. AG changes no interaction.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Resolve the campus from the student number (C1)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Create `Core/Campus.swift` and `Tests/PUPSISPortalTests/CampusTests.swift`.
- [ ] Edit `Core/Preferences.swift` (`campusOverride`, `learnedCampusCodes`, both cleared on sign-out), `Views/Landing/SignInPanel.swift`, `Views/Landing/PortalScene.swift` (hub tag) and `Views/Shell/Sidebar.swift` (footer chip).

**Build.**

- [ ] Spec 10 in full, except the Settings picker, which lands in SE.
- [ ] Only `MN` maps to a campus. Other codes resolve to `.unknownCode` and show "Pick your campus".

**You see.**

- [ ] Typing `2026-00000-MN-0` on the sign-in panel shows the "campus found" line for MN · Sta. Mesa, and the sidebar footer reads "MN · Sta. Mesa".

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `CampusTests` covers every case in spec 10's first acceptance box. Run `swift test --filter CampusTests`.
- [ ] A test asserts sign-out clears `campusOverride` and `learnedCampusCodes`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot the sign-in panel empty on trunk and head. Save `signin-trunk.png` and `signin-head.png`. Pass when only the campus line differs.
- [ ] Lane 2. Snapshot the panel with `2026-00000-MN-0`. Save `campus-mn.png`. Pass when it shows the "campus found" line for MN · Sta. Mesa.
- [ ] Lane 3. Snapshot with `2026-00000-TG-0`. Save `campus-tg.png`. Pass when it shows the TG chip and "Pick your campus".
- [ ] Lane 4. Snapshot with `2026-000`. Save `campus-partial.png`. Pass when it reads "Your campus shows up as you type."
- [ ] Lane 5. Snapshot the sidebar. Save `sidebar-chip.png`. Pass when the footer chip reads "MN · Sta. Mesa".
- [ ] Lane 6. Snapshot the hub. Save `hub-tag.png`. Pass when the tag reads "PUP SIS / Sta. Mesa · via sis8".
- [ ] Lane 7. Live, pick a campus for TG, sign out and back in with TG. Save `learned.png`. Pass when TG resolves only while signed in, and is cleared after sign-out.
- [ ] Lane 8. Snapshot at UI scale 140. Save `scale.png`. Pass when the chip does not clip.
- [ ] Lane 9. VoiceOver label check through `accessibilityLabel` in a test. Save `a11y.png` of the test log. Pass when the chip reads "Campus, Sta. Mesa".
- [ ] Lane 10. `log stream` during sign-in. Save `net.png`. Pass when no request carries the campus.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Keystroke to campus-line update.
- [ ] Probe. A test times `CampusCatalog.resolve` over 10,000 calls.
- [ ] Baseline. No trunk equivalent. Absolute budget.
- [ ] Rule. Under 5ms total for 10,000 calls.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2 to 6 screenshots and a video (or a snapshot strip until Screen Recording is granted) to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Rebuild the Schedule chrome and turn weeks in 3D (SC1)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Edit `Views/CalendarView.swift`, `Views/WeekGrid.swift`, `Views/Blocks.swift`, `Views/NowLine.swift` and `Views/CalendarScroll.swift`. Add `Tests/PUPSISPortalTests/ScheduleSnapshotTests.swift`.

**Build.**

- [ ] Spec 03 UX changes 1, 2, 5 and 6. The toolbar row, the COR strip, notched blocks with stamps, the gold today wash and the gold now-line with its time chip.
- [ ] Paging weeks with ⌘[ / ⌘] and the arrows plays `WeekTurn` (cube). A key pressed mid-turn redirects it.
- [ ] Fix the known today-dither CPU cost (about 21% in Debug) while touching `WeekGrid`.

**You see.**

- [ ] ⌘] turns the grid like a cube face to next week, in under 500ms.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `GridGeometryTests`, `TimeSnapTests` and the `EventEditor` tests still pass.
- [ ] A test asserts `WeekTurn` direction, where forward rotates negative and back rotates positive. Run `swift test --filter DepthTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot Schedule on trunk and head. Save `week-trunk.png` and `week-head.png`. Pass when every class block from trunk is on head at the same time.
- [ ] Lane 2. Snapshot light and dark at 1280x820. Save `week-light.png` and `week-dark.png`. Pass when it matches the prototype layout.
- [ ] Lane 3. Snapshot `WeekTurn` at progress 0.5. Save `turn-mid.png`. Pass when both weeks show with no gap.
- [ ] Lane 4. Live, press ⌘] then ⌘[ quickly. Save `turn-redirect.png`. Pass when the grid ends on the starting week.
- [ ] Lane 5. Live, drag to create an event. Save `create.png`. Pass when "New Event" appears and saves.
- [ ] Lane 6. Live, resize a repeating event. Save `repeat.png`. Pass when the This Event Only / All Future Events prompt shows.
- [ ] Lane 7. Live, ⌘-drag a band and press ⌫. Save `multi.png`. Pass when the selection bar shows "N selected" and delete undoes with ⌘Z.
- [ ] Lane 8. Snapshot a vacant, an online and an in-person block. Save `stamps.png`. Pass when each shows its stamp and vacant is hatched.
- [ ] Lane 9. Force Reduce Motion and page a week. Save `reduced.png`. Pass when the week swaps with no rotation.
- [ ] Lane 10. Snapshot the year view. Save `year.png`. Pass when clicking a day opens that week.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Idle CPU on Schedule, and frame time during a week turn.
- [ ] Probe. `ps -o %cpu` for 30 seconds on trunk and head, three runs each. `MTL_HUD_ENABLED=1` during ten turns.
- [ ] Baseline. Trunk Schedule idle median first.
- [ ] Rule. Head idle under trunk, since the dither fix lands here. Turns hold 60 fps.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 3, 8 screenshots and a video of a week turn to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Add the COR view and the class inspector (SC2)

**Depends on.** SC1.

**Files.**

- [ ] Create `Views/Schedule/CORView.swift` and `Views/Schedule/ClassInspector.swift`. Edit `Views/CalendarView.swift` and `Views/Blocks.swift`. Delete `Views/ScheduleSidebar.swift` once its content has moved.

**Build.**

- [ ] Spec 03 UX changes 3, 4 and 7. Week | COR | Year in the toolbar. The COR table counts Lab and Lec units once. The 290pt inspector replaces the class popover. Print moves to the toolbar ⋯ menu.

**You see.**

- [ ] Clicking a class slides in the inspector, and "Online" thunks a stamp onto the block.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] A test asserts COR total units for a week with a Lab and Lec pair. Run `swift test --filter CORTests`.
- [ ] The `Notifier` test covers a status change from the inspector.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Open a class popover on trunk and the inspector on head. Save `popover-trunk.png` and `inspector-head.png`. Pass when every popover field exists in the inspector.
- [ ] Lane 2. Snapshot the COR view. Save `cor.png`. Pass when the total units match SIS.
- [ ] Lane 3. Stamp a class Online. Save `stamp-online.png`. Pass when grid, COR and Today all show Online.
- [ ] Lane 4. Set "Every week this term". Save `every-week.png`. Pass when next week shows the same stamp.
- [ ] Lane 5. Override a class time and Reset. Save `time-reset.png`. Pass when the SIS time label returns.
- [ ] Lane 6. Change a class colour. Save `colour.png`. Pass when the block and COR row recolour.
- [ ] Lane 7. Open files and links in the inspector. Save `links.png`. Pass when the former sidebar links are there.
- [ ] Lane 8. Print from the ⋯ menu. Save `print.png`. Pass when the print sheet opens.
- [ ] Lane 9. Reduce Motion, open the inspector. Save `reduced.png`. Pass when it appears with no slide and no thunk.
- [ ] Lane 10. VoiceOver on the stamp buttons. Save `vo.png`. Pass when they read as a radio group.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Click to inspector first frame.
- [ ] Probe. Twenty clicks through `osascript` on trunk (popover) and head (inspector), interleaved.
- [ ] Baseline. Trunk popover median first.
- [ ] Rule. Head within 50ms of trunk.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 3 screenshots and a video of stamping to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Rebuild Grades (G)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Replace `Views/GradesView.swift` with `Views/Grades/GradesScreen.swift`, `GPATrendChart.swift` and `GradesTable.swift`. Add `GradesSnapshotTests`.

**Build.**

- [ ] Spec 05 in full. Term sheet with the GPA hero, pixel trend chart, grades table, and a third sheet for Units completed and What do I need. GPA everywhere, never GWA.

**You see.**

- [ ] Grades opens on the posted term with the GPA in display 56 and the trend's last point labelled.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `GradesParserTests` pass. Run `swift test --filter Grades`.
- [ ] A test asserts the trend's VoiceOver summary for an improving and a falling term.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot Grades on trunk and head. Save `grades-trunk.png` and `grades-head.png`. Pass when the GPA and every grade match.
- [ ] Lane 2. Snapshot light and dark. Save `grades-light.png` and `grades-dark.png`. Pass when it matches the prototype.
- [ ] Lane 3. Snapshot a term with pending subjects. Save `pending.png`. Pass when they read "Pending".
- [ ] Lane 4. Snapshot an empty term. Save `empty.png`. Pass when the dithered "No grades yet" shows.
- [ ] Lane 5. Live, Load past terms. Save `backfill.png`. Pass when older terms join the picker.
- [ ] Lane 6. Live, What do I need with a target of 1.50. Save `need.png`. Pass when it answers on the 1.00 to 5.00 scale.
- [ ] Lane 7. Snapshot with no program units set. Save `units.png`. Pass when it points to Settings.
- [ ] Lane 8. Grep for "GWA". Save `gwa.png`. Pass when nothing matches in Views.
- [ ] Lane 9. Snapshot at UI scale 80 and 140. Save `scales.png`. Pass when the table does not clip.
- [ ] Lane 10. Check small digits. Save `digits.png`. Pass when every number under 20pt uses `Typography.numeric`.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Grades first frame.
- [ ] Probe. `Snapshot.render` timed ten times on trunk and head, interleaved.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 20 percent of trunk.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 3, 4 screenshots and a video to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Restyle the menu bar panel (MB)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Edit `Views/MenuBarPanel.swift`. Add `MenuBarSnapshotTests`.

**Build.**

- [ ] Spec 08. Sheet styling, codes in display face with subject colour, stamps, gold now marker, campus chip once C1 lands (a placeholder slot until then), and "Open IntPortal".

**You see.**

- [ ] The menu bar panel matches the sheets in the app, and its label text is unchanged.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `DayAgendaTests` pass. Run `swift test --filter DayAgendaTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot the panel on trunk and head. Save `mb-trunk.png` and `mb-head.png`. Pass when the same rows show.
- [ ] Lane 2. Snapshot with a class in 12 minutes. Save `soon.png`. Pass when "Up next" shows it.
- [ ] Lane 3. Snapshot with classes later today. Save `later.png`. Pass when "Later today" lists them with "now".
- [ ] Lane 4. Snapshot after the last class. Save `tomorrow.png`. Pass when "Tomorrow · CODE at …" shows.
- [ ] Lane 5. Snapshot signed out. Save `signed-out.png`. Pass when it reads "Sign in to see your schedule."
- [ ] Lane 6. Snapshot at week end. Save `week-end.png`. Pass when it reads "No more classes this week."
- [ ] Lane 7. Snapshot reminders on and off. Save `reminders.png`. Pass when both lines read correctly.
- [ ] Lane 8. Snapshot dark. Save `dark.png`. Pass when contrast holds.
- [ ] Lane 9. Live, click "Open IntPortal". Save `open.png`. Pass when the main window comes forward.
- [ ] Lane 10. Snapshot an online and a vacant class. Save `stamps.png`. Pass when each shows its stamp.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Idle CPU with the panel closed.
- [ ] Probe. `ps -o %cpu` for 30 seconds, trunk then head, three runs.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 0.5 points.

**Review gate.** None. MB is a restyle with the same content.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Add the pure study models (ST1)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Create `Core/Study/Mastery.swift`, `DueForecast.swift`, `GapSuggestion.swift`, `ExamLink.swift`, `StudyMap.swift`, `WeakList.swift` and `Tests/PUPSISPortalTests/StudyTests.swift`.

**Build.**

- [ ] Spec 11 upgrades 1, 2, 3, 4, 6 and 7 as pure functions over the data the stores already hold. No UI.

**You see.**

- [ ] Nothing on screen yet. `StudyTests` pass.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `StudyTests` covers spec 11's `StudyTests` acceptance box with literal expected values. Run `swift test --filter StudyTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Run `swift test` on trunk and head. Save `tests.png` of both counts. Pass when head adds tests and fails none.
- [ ] Lane 2. Mastery of a new deck. Save `mastery-new.png` of the test log. Pass when it is 0, not 1 − due/total.
- [ ] Lane 3. Mastery after two Good reviews a week apart. Save `mastery-grown.png`. Pass when the card counts as mastered.
- [ ] Lane 4. DueForecast across a DST change. Save `forecast-dst.png`. Pass when seven buckets start today.
- [ ] Lane 5. GapSuggestion with a tie on due count. Save `gap-tie.png`. Pass when the nearer exam wins.
- [ ] Lane 6. GapSuggestion with a 10-minute gap. Save `gap-short.png`. Pass when minutes cap at the gap.
- [ ] Lane 7. ExamLink with no shared topic token. Save `examlink-none.png`. Pass when no deck links.
- [ ] Lane 8. StudyMap tower height as days fall. Save `towers.png`. Pass when height rises monotonically and caps.
- [ ] Lane 9. WeakList ordering. Save `weak.png`. Pass when the top 3 by Again count in 30 days come first.
- [ ] Lane 10. Grep `Core/Study` for `import SwiftUI`. Save `pure.png`. Pass when nothing matches.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. `StudyMap.layout` and `DueForecast.next7` time over 2,000 cards.
- [ ] Probe. A test times ten runs.
- [ ] Baseline. No trunk equivalent. Absolute budget.
- [ ] Rule. Under 10ms per run.

**Review gate.** None. ST1 has no UI.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Rebuild Today (T1)

**Depends on.** AG and ST1.

**Files.**

- [ ] Edit `Views/Today/TodayScreen.swift` (from AG). Add `TodaySnapshotTests`.

**Build.**

- [ ] Spec 04 Today. Your day timeline sheet and the This term and Due soon rail. Free rows with dithered gold bars, the Now line inside its free row, and "Study in this gap" from `GapSuggestion`.
- [ ] Day notes and the day navigator move to Notebook as "Today's note".

**You see.**

- [ ] Today shows the day's classes with Done, In session or a countdown, and a free row suggests a deck to study.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `DayAgendaTests` pass. Run `swift test --filter DayAgendaTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot Today on trunk and head at the same fixed time. Save `today-trunk.png` and `today-head.png`. Pass when every row from trunk is on head.
- [ ] Lane 2. Snapshot light and dark. Save `today-light.png` and `today-dark.png`. Pass when it matches the prototype.
- [ ] Lane 3. Snapshot during a class. Save `in-session.png`. Pass when it reads "In session".
- [ ] Lane 4. Snapshot in a free gap with a due deck. Save `gap.png`. Pass when "Study in this gap" names the deck and minutes.
- [ ] Lane 5. Snapshot an empty day. Save `empty.png`. Pass when it reads "Nothing scheduled today." and the Tomorrow line.
- [ ] Lane 6. Snapshot with an exam in 4 days. Save `due-soon.png`. Pass when the tile shows 4 days in `bad`.
- [ ] Lane 7. Live, click Start in the gap. Save `start.png`. Pass when the deck opens in Flashcards.
- [ ] Lane 8. Live, open Today's note from Notebook. Save `todays-note.png`. Pass when it opens today's day note.
- [ ] Lane 9. VoiceOver on a row. Save `vo.png`. Pass when it reads "COMP 002 lecture, 9 to 12, done".
- [ ] Lane 10. Snapshot at UI scale 140. Save `scale.png`. Pass when the rail does not clip.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Idle CPU on Today.
- [ ] Probe. `ps -o %cpu` for 30 seconds, trunk then head, three runs.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 1 point.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 4, 6 screenshots and a video to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Rebuild the Notebook (T2)

**Depends on.** AG.

**Files.**

- [ ] Edit `Views/Notebook/NotebookScreen.swift`, `Views/WebNoteEditor.swift`, `notes-editor/src/editor.css` and `notes-editor/src/editor.js` (`PUPNotes.setTheme`). Move the formatting toolbar out of `Views/AssistantFloating.swift` into `Views/Notebook/FormattingToolbar.swift`. Rebuild `Resources/notes-editor.bundle.js`.

**Build.**

- [ ] Spec 04 Notebook. Vault sheet, editor sheet with kicker and display title, grouped labelled toolbar, `setTheme` from Swift, empty editor state, titles never raw prompts.

**You see.**

- [ ] The toolbar sits above the editor with every button labelled, and dark mode reaches the editor.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `NotesStoreTests` pass. Run `swift test --filter NotesStoreTests`.
- [ ] A test asserts the vault title for a note with only an AI prompt is its first heading.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot the vault on trunk and head. Save `vault-trunk.png` and `vault-head.png`. Pass when the same notes and folders show.
- [ ] Lane 2. Live, light and dark. Save `editor-light.png` and `editor-dark.png`. Pass when the editor follows the theme.
- [ ] Lane 3. Live, bold, math and a table from the toolbar. Save `toolbar.png`. Pass when each inserts.
- [ ] Lane 4. Live, drag a note into a folder. Save `drag.png`. Pass when it moves and persists after relaunch.
- [ ] Lane 5. Live, export a note to PDF. Save `export.png`. Pass when the file writes.
- [ ] Lane 6. Live, toggle Include in AI search. Save `ai-search.png`. Pass when the count and sparkle update.
- [ ] Lane 7. Live, paste an image and a `[[wikilink]]`. Save `paste.png`. Pass when both render.
- [ ] Lane 8. Snapshot with no note open. Save `empty.png`. Pass when it reads "Pick a note or start one".
- [ ] Lane 9. Accessibility Inspector on the toolbar. Save `a11y.png`. Pass when every button has a label.
- [ ] Lane 10. Live, Ask AI Summarize on a selection. Save `ask-ai.png`. Pass when the preview offers Replace, Insert below and Copy.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Note open to first editor paint.
- [ ] Probe. Open twenty notes through `osascript` on trunk and head, interleaved, reading a signpost.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 50ms of trunk.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 3, 8 screenshots and a video to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Rebuild the Quizzes screen with the deck fan (ST2)

**Depends on.** AG and ST1.

**Files.**

- [ ] Edit `Views/Quiz/QuizzesScreen.swift` (from AG) and `Views/Quiz/QuizVisuals.swift`. Create `Views/Quiz/StudyMapView.swift`, `DeckTile.swift`, `ExamBanner.swift` and `StudyHeatmap.swift`.

**Build.**

- [ ] Spec 11 layout for Quizzes. Exam banner, study map (Canvas, with an accessibility list), heatmap and weak list, deck tiles with card stacks, mastery bars and forecast bars.
- [ ] Opening a deck plays `DeckFan`. Fan width is the due count, then the first card deals to center.

**You see.**

- [ ] Opening a deck with 23 due fans visibly wider than one with 7.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `DepthTests` and `StudyTests` pass. Run `swift test --filter "DepthTests|StudyTests"`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot Quizzes on trunk and head. Save `quizzes-trunk.png` and `quizzes-head.png`. Pass when every deck and the streak show.
- [ ] Lane 2. Snapshot light and dark. Save `quizzes-light.png` and `quizzes-dark.png`. Pass when it matches the prototype.
- [ ] Lane 3. Snapshot `DeckFan` at 7 and 23. Save `fan-7.png` and `fan-23.png`. Pass when 23 is wider.
- [ ] Lane 4. Snapshot an exam within 14 days. Save `exam.png`. Pass when the banner shows the day count and linked deck.
- [ ] Lane 5. Snapshot the study map. Save `map.png`. Pass when a tower stands on the exam topic.
- [ ] Lane 6. Snapshot with no decks. Save `empty.png`. Pass when the empty copy shows and the map is unlit.
- [ ] Lane 7. Live, deck menu Rename and Delete. Save `menu.png`. Pass when delete asks to confirm.
- [ ] Lane 8. Live, Generate deck with AI off. Save `ai-off.png`. Pass when it is disabled with the tooltip.
- [ ] Lane 9. Reduce Motion, open a deck. Save `reduced.png`. Pass when the first card shows directly.
- [ ] Lane 10. VoiceOver on the map. Save `vo.png`. Pass when it reads subject, topic, mastery and exam days.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Quizzes idle CPU and fan frame time.
- [ ] Probe. `ps -o %cpu` for 30 seconds three runs, and the Metal HUD over ten fans.
- [ ] Baseline. Trunk Quizzes idle median first.
- [ ] Rule. Idle within 1 point of trunk. Fan holds 60 fps.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 3, 5 screenshots and a video of the fan to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Rebuild the study modes and the recap (ST3)

**Depends on.** ST1.

**Files.**

- [ ] Edit `Views/Quiz/StudySession.swift`, `IdentificationSession.swift`, `MultipleChoiceSession.swift`, `TrueFalseSession.swift`, `MatchingSession.swift` and `QuizModePicker.swift`. Create `Views/Quiz/SessionRecap.swift`.

**Build.**

- [ ] Spec 11 upgrades 8 and 9. Shared header, 3D flip with FSRS intervals under each rating, keys for every action, Auto-advance toggle, and the recap with real next due dates.

**You see.**

- [ ] Finishing a session shows accuracy, the streak step and each card's next due date.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] A test on the session reducer asserts recap due dates equal the FSRS output. Run `swift test --filter Session`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Run a Flashcards session on trunk and head. Save `flash-trunk.png` and `flash-head.png`. Pass when the same ratings exist.
- [ ] Lane 2. Flashcards keyboard only (Space, 1 to 4). Save `flash-keys.png`. Pass when the session completes.
- [ ] Lane 3. Identification wrong answer. Save `why.png`. Pass when "Why?" explains.
- [ ] Lane 4. Multiple Choice keys 1 to 4. Save `mc.png`. Pass when the correct option colours.
- [ ] Lane 5. True or False keys T and F. Save `tf.png`. Pass when both answer.
- [ ] Lane 6. Matching with one miss. Save `match.png`. Pass when the miss shakes and rates Again.
- [ ] Lane 7. Recap. Save `recap.png`. Pass when due dates match the FSRS log.
- [ ] Lane 8. Auto-advance off. Save `auto-off.png`. Pass when the session waits after a correct answer.
- [ ] Lane 9. Reduce Motion. Save `reduced.png`. Pass when faces swap with no flip.
- [ ] Lane 10. A deck with 3 cards in Matching. Save `too-few.png`. Pass when it reads "Needs ≥4 cards".

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Flip frame time.
- [ ] Probe. Metal HUD over twenty flips.
- [ ] Baseline. Trunk flip first.
- [ ] Rule. 60 fps on both.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 7 screenshots and a video of a session to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Make the Syllabus editable (ST4)

**Depends on.** AG and ST1.

**Files.**

- [ ] Edit `Views/Syllabus/SyllabusScreen.swift` (from AG), `Views/SyllabusView.swift`, `SyllabusImportSheet.swift` and `SyllabusReviewSheet.swift`.

**Build.**

- [ ] Spec 11 upgrade 10 and the Syllabus layout. Mark done and Undo through `completedOverride`, the gold This week line, Quiz me on lectures, exam lines with linked due counts, edit and delete.
- [ ] Give `exportSyllabusDeadlines` the same stale-event sweep fix `exportSchedule` got in W5.

**You see.**

- [ ] Clicking Mark done on a lecture checks it off and it stays done after relaunch.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] A test asserts `completedOverride` persists across a store reload. Run `swift test --filter Syllabus`.
- [ ] A test asserts re-exporting deadlines removes events for deleted items.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot Syllabus on trunk and head. Save `syl-trunk.png` and `syl-head.png`. Pass when every item shows.
- [ ] Lane 2. Snapshot light and dark. Save `syl-light.png` and `syl-dark.png`. Pass when it matches the prototype.
- [ ] Lane 3. Mark done, relaunch. Save `done.png`. Pass when it stays done.
- [ ] Lane 4. Quiz me on a lecture. Save `quiz-me.png`. Pass when Generate opens prefilled.
- [ ] Lane 5. Snapshot an exam item. Save `exam.png`. Pass when it shows days left and due cards.
- [ ] Lane 6. Edit an item. Save `edit.png`. Pass when the change persists.
- [ ] Lane 7. Delete an item and re-export. Save `export.png`. Pass when its calendar event is gone.
- [ ] Lane 8. Add syllabus by Paste text. Save `add.png`. Pass when extraction reaches the review sheet.
- [ ] Lane 9. Grading calculator. Save `calc.png`. Pass when it reads "Average X% on what's left…".
- [ ] Lane 10. Snapshot a generated syllabus. Save `disclaimer.png`. Pass when the disclaimer banner shows.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Syllabus first frame with 60 items.
- [ ] Probe. `Snapshot.render` timed ten times on trunk and head.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 20 percent.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 3, 5 screenshots and a video to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Restyle and split IntAssis (AS)

**Depends on.** T2.

**Files.**

- [ ] Replace `Views/AssistantFloating.swift` with `Views/Assistant/AssistantOrb.swift`, `AssistantChatPanel.swift`, `AssistantHelpPopover.swift`, `AssistantThinkingPopover.swift` and `ActionRow.swift`, each under 400 lines.

**Build.**

- [ ] Spec 06 in full. Ink-square orb, pixel rail chips per screen, sheet chat panel with no glass, header mode select, "Runs on {provider}" copy.
- [ ] While a request runs the mark becomes `VoxelOrb`, in the chat header when open and on the orb when closed.

**You see.**

- [ ] Asking a question turns the orb into a spinning voxel cube until the reply lands.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The assistant tests pass unchanged. Run `swift test --filter Assistant`.
- [ ] `git diff --stat origin/main -- Sources/PUPSISPortalApp/Core` prints nothing.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot the open chat on trunk and head. Save `chat-trunk.png` and `chat-head.png`. Pass when every header control exists.
- [ ] Lane 2. Snapshot the orb thinking and idle. Save `orb-think.png` and `orb-idle.png`. Pass when it is a cube while thinking.
- [ ] Lane 3. Live, `/week`. Save `week.png`. Pass when the reply lists the week.
- [ ] Lane 4. Live, an add_event in Confirm each action. Save `action.png`. Pass when the row offers Skip and Apply.
- [ ] Lane 5. Live, `/` autocomplete with arrows and Tab. Save `autocomplete.png`. Pass when it fills the command.
- [ ] Lane 6. Live, the help popover. Save `help.png`. Pass when the groups and footer copy show.
- [ ] Lane 7. Live, the thinking popover. Save `thinking.png`. Pass when Off, Low, Medium and Max show.
- [ ] Lane 8. Snapshot with a cloud provider set. Save `provider.png`. Pass when it reads "Runs on {provider}".
- [ ] Lane 9. Reduce Motion. Save `reduced.png`. Pass when there is no word reveal and the cube is static.
- [ ] Lane 10. Snapshot the rail on Grades. Save `rail.png`. Pass when it shows GPA trend and Next class.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Idle CPU with the orb shown, chat closed.
- [ ] Probe. `ps -o %cpu` for 30 seconds, three runs, trunk then head.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 0.5 points.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 4 screenshots and a video of a question and reply to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Make Settings a screen with one file per pane (SE)

**Depends on.** C1 and #26 (W10).

**Files.**

- [ ] Replace `Views/SettingsView.swift` with `Views/Settings/SettingsScreen.swift` and one file per pane. Edit `Views/Shell/AppShell.swift` and `App/PUPSISPortalApp.swift` so ⌘, opens the screen.

**Build.**

- [ ] Spec 07 in full. Dynamic Island group removed, Play portal intro kept, Campus picker (spec 10), SIS server row, Back to the portal hub, the Intelligence cloud note.

**You see.**

- [ ] ⌘, opens Settings in the main window with a pane column on the left.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `PreferencesTests` pass. Run `swift test --filter PreferencesTests`.
- [ ] Every pane file is under 350 lines. Run `wc -l Sources/PUPSISPortalApp/Views/Settings/*.swift`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Snapshot every pane on trunk and head. Save `panes-trunk.png` and `panes-head.png`. Pass when every control from trunk exists, except the Dynamic Island group.
- [ ] Lane 2. Snapshot light and dark. Save `settings-light.png` and `settings-dark.png`. Pass when it matches the prototype.
- [ ] Lane 3. Live, Reset This Pane on Appearance. Save `reset.png`. Pass when only that pane resets.
- [ ] Lane 4. Live, pick a campus. Save `campus.png`. Pass when the sidebar chip and hub tag update.
- [ ] Lane 5. Live, turn off Play portal intro, relaunch. Save `no-intro.png`. Pass when the app opens on Today.
- [ ] Lane 6. Live, Back to the portal hub. Save `hub.png`. Pass when the hub shows.
- [ ] Lane 7. Live, UI scale 140. Save `scale.png`. Pass when nothing clips.
- [ ] Lane 8. Live, Sign Out. Save `sign-out.png`. Pass when the landing shows and the campus clears.
- [ ] Lane 9. Snapshot Intelligence with a cloud provider. Save `cloud.png`. Pass when the Keychain note names the provider.
- [ ] Lane 10. Live, Check for Updates. Save `updates.png`. Pass when Sparkle answers.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. ⌘, to first frame.
- [ ] Probe. Twenty presses through `osascript` on trunk (sheet) and head (screen), interleaved.
- [ ] Baseline. Trunk median first.
- [ ] Rule. Head within 50ms of trunk.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2, 4 screenshots and a video of the panes to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Render the HyperFrames trailer (HF)

**Depends on.** Phase 1 merged (#24).

**Files.**

- [ ] Create `docs/media/trailer/` (the HyperFrames project) and `docs/media/trailer.mp4`. Edit `README.md` to show the trailer.

**Build.**

- [ ] A 30 to 45 second MP4 from `intportal-v3.html`. Void, portal forming, the hub ring, the warp, then Today, Schedule with a week turn, Grades and a deck fan. Placeholder data only.

**You see.**

- [ ] The README opens with the trailer.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `ffprobe docs/media/trailer.mp4` reports a duration between 30 and 45 seconds.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Render the README on trunk and head. Save `readme-trunk.png` and `readme-head.png`. Pass when only the trailer is added.
- [ ] Lane 2. Frame at 2s. Save `f02.png`. Pass when the void and forming portal show.
- [ ] Lane 3. Frame at the hub. Save `hub.png`. Pass when the ring shows PUP SIS lit.
- [ ] Lane 4. Frame at the warp flash. Save `warp.png`. Pass when the pixelate shows.
- [ ] Lane 5. Frame at Today. Save `today.png`. Pass when the timeline shows.
- [ ] Lane 6. Frame at the week turn. Save `turn.png`. Pass when the cube is mid-turn.
- [ ] Lane 7. Frame at the deck fan. Save `fan.png`. Pass when the fan shows.
- [ ] Lane 8. Scan every frame for a real student number or name. Save `pii.png`. Pass when only placeholders appear.
- [ ] Lane 9. Check the file size. Save `size.png`. Pass when it is under 15 MB.
- [ ] Lane 10. Check the app bundle. Save `bundle.png`. Pass when no `.mp4` is in `IntPortal.app`.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Dropped frames in the MP4.
- [ ] Probe. `ffprobe -count_frames` against the expected frame count.
- [ ] Baseline. The expected count at 30 fps.
- [ ] Rule. No dropped frames.

**Review gate.** The operator reviews before merge.

- [ ] Post lanes 2 to 7 screenshots and the video to the operator in chat.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Refresh the feature docs (DOCS)

**Depends on.** Every other slice merged.

**Files.**

- [ ] Edit `docs/FEATURES.md` and `PRODUCT.md`. Owner is the `pupsis-docs` agent.

**Build.**

- [ ] Replace Ollama with llama.cpp and MLX plus optional cloud providers. Replace "Settings → Misc" with Settings › Intelligence. Describe the portal landing, the sidebar and each rebuilt screen.

**You see.**

- [ ] `docs/FEATURES.md` describes the app as it ships after phase 2.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `grep -rn "Ollama\|Settings → Misc" docs/FEATURES.md PRODUCT.md` prints nothing.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, run in sequence by one verifier.

- [ ] Lane 1. Regression against trunk. Diff the headings. Save `headings.png`. Pass when no section is lost.
- [ ] Lane 2. Check the landing section against the app. Save `landing.png`. Pass when every claim holds.
- [ ] Lane 3. Check Schedule. Save `schedule.png`. Pass when every claim holds.
- [ ] Lane 4. Check Today and Notebook. Save `today.png`. Pass when every claim holds.
- [ ] Lane 5. Check Grades. Save `grades.png`. Pass when every claim holds.
- [ ] Lane 6. Check Quizzes and Syllabus. Save `study.png`. Pass when every claim holds.
- [ ] Lane 7. Check IntAssis. Save `assistant.png`. Pass when the tool list matches `AssistantTool.swift`.
- [ ] Lane 8. Check Settings. Save `settings.png`. Pass when every pane matches.
- [ ] Lane 9. Check shortcuts. Save `shortcuts.png`. Pass when ⌘0 to ⌘6 and ⌘, match `Destination`.
- [ ] Lane 10. Run unslop over both files. Save `unslop.png`. Pass when no rule fires.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. None applies to docs. Recorded as n/a.
- [ ] Probe. n/a.
- [ ] Baseline. n/a.
- [ ] Rule. n/a.

**Review gate.** None. Docs only.

**Merge.**

- [ ] Clean verdict at the head SHA, then the operator merges.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Rebuild and install the app with `Scripts/make_mac_app.sh` from `origin/main`.
- [ ] Reply to the operator with each PR link, its verdict, and anything parked.

## Appendix A. Prototype evidence

- Prototype v3 (`docs/specs/prototypes/intportal-v3.html`, artifact version 4) proved every 3D move used here. The operator picked the cube week turn and the push screen change on 2026-09-23.
- Unproven until ST2 lands is whether the study map reads as information at 1280x820 rather than decoration. ST2 lane 5 and lane 10 decide it.

## Appendix B. Carried over from phase 1

- Live checks never run are the warp frame rate, Release CPU of the hub, the SIS logout selector, `WKWebsiteDataRecord.displayName`, the export calendar switch, `--api-key-file` on the CI llama-server.
- Sheet labels with digits in some Pixel components still use Pixelify. Each slice fixes the ones it touches.
- The `/rag` path always runs locally, even with a cloud provider. AS keeps that and says so in the help popover.

## Appendix C. Risks

- Screen Recording is not granted, so live screenshots and videos wait on the operator. Snapshot lanes cover layout in the meantime.
- Sonnet rate limits stalled phase 1 twice. Four workers at a time, and the tick restarts a stalled one.
- `AppShell.swift` is the one shared file. Slices touch only their own case line.

## Appendix D. Revisions

2026-09-24 and 25, after the user asked to keep their custom environment and to take the most
efficient path (wayfinder map "Custom environment in the new UI").

- **RS, restyle through the style layer (head, #40).** The glass helpers, `canvasWash` and the
  scene tint now draw Registrar chrome, so every older screen takes the new look at once. Slices
  below change layout and behaviour only; none repaints a screen by hand.
- **TH, theme roles for every room (head, #35).** Every room paints the shell through derived
  roles.
- **Hotfix (#39).** The sync ripple's always-on `layerEffect` blanked AppKit-backed content in
  every screen; the ripple is an overlay now.
- **IP, island prototype (head).** Spec 12 in prototype v3, artifact v5, then the user's review.
- **IS, native island (after IP).** `IslandGlance` plus `Island` in the shell, hosting each
  screen's controls; replaces the slim controls row SC1 left above the COR strip.
- **SE moves up** to right after TH, with the audit fixes in spec 07 point 3b.
- **SC1** builds `ScheduleControls` for the island instead of a header toolbar row (#37).
- **T2** keeps the formatting toolbar in the floating deck; AS restyles and labels it there.
- **Verification** is the snapshot suite plus live captures now that Screen Recording is
  granted. The ten-lane swarm per PR is dropped for slices whose only change is layout; the head
  reads every capture before a PR opens.
