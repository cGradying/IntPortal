# IntPortal UI revision, phase 1 plan

Students who open IntPortal get the approved "Portal and the Registrar" design, built natively in SwiftUI and Metal, with motion tuned to feel like macOS 27. Grilling round, 2026-09-23. The user picked motion and depth without glass, SwiftUI plus Metal as the only 3D engine, and HyperFrames for the product trailer and README only.
The user chose these new 3D moments. A campus carousel on the hub, a cube turn when paging Schedule weeks, and depth transitions between screens with a voxel IntAssis orb. A sync ripple from the portal glyph, and a deck fan whose width is the due count.
The rule the program enforces is the one in DESIGN.md. Every 3D or dithered element encodes a number or a state, and every animation routes through `Motion` and vanishes under Reduce Motion.
Phase 1 is the foundation the user asked the head (Opus, main chat) to build, in five PRs. P3, then F1, F2, F3, S1, L1. Phase 2, which covers the screen slices built by sonnet workers, is planned in `docs/specs/PLAN-2.md` once L1 is stack-ready.
Target repo is IntPortal. This file is `docs/specs/PLAN.md`, linted by pstack's `check-plan.mjs`.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-stack.md`. The user asked for the most control, so no PR merges itself. The head builds P3, F1, F2, F3, S1 and L1, verifies each, and appends it to one linear stack on `main`. The operator (the user) reviews and lands every PR. P3, F2, F3, S1 and L1 are review-gated and stop at stack-ready.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on the operator's explicit go.
- [ ] On the operator's go, arm a `/goal` with this exact text. "Run docs/specs/PLAN.md in IntPortal. PRs P3, F1, F2, F3, S1, L1 in that order. A PR is verified only when its unit, live, and perf boxes are all checked. The head builds and verifies and the operator lands every PR. Done when all six are stack-ready with clean verdicts and PLAN-2.md is written."
- [ ] Unblock the build (step 0 of `docs/specs/README.md`).
  - [ ] Run `xcodebuild -downloadComponent MetalToolchain`. Evidence is `xcodebuild -showComponent MetalToolchain` printing `Status: installed`.
  - [ ] Run `swift build` and `swift test` on `main`. Evidence is both exit codes 0, saved to `.claude/plans/logs/step0.txt`.
- [ ] Land the docs before any code, on branch `docs/ui-revision-specs` from `main`. Stage only `docs/specs/`, `DESIGN.md`, `.gitignore`, `CONTEXT.md` and `docs/adr/`. Leave the operator's `docs/web/*` and `today-cell-zoom.png` untouched. No Claude co-author trailer.
  - [ ] DESIGN.md gains a section named "macOS 27 motion and depth". Springs are fast and interruptible. Floating layers get a darkened edge and a bright top highlight. Each screen has one uniform toolbar row. The active window casts a stronger shadow. Glass stays retired.
  - [ ] DESIGN.md Signature components and the Motion table gain `orbit` (hub carousel), `turn` (week cube), `depthPush` (screen change), `ripple` (sync), `fan` (deck fan-out) and `think` (voxel orb), each with the number it encodes.
  - [ ] Specs 01, 03, 06, 09 and 11 each gain their 3D item and an acceptance box for it. README index gains PLAN.md, prototype v3 and the HyperFrames trailer.
  - [ ] Create `CONTEXT.md` as a glossary. Portal is the obsidian gate you step through. Hub is the room of portals. Warp is the dive into a portal. SIS is PUP's website. Host is one SIS server such as sis8. Campus is the school the student number names. The Registrar is the in-app world. The void is the landing space.
  - [ ] Create `docs/adr/0001-swiftui-metal-no-glass.md`. It records choosing SwiftUI plus Metal over RealityKit and three.js, and pixel sheets over Liquid Glass on macOS 27.
  - [ ] Open the docs PR with `gh pr create --base main`. Evidence is the PR URL. The operator merges it before P3 starts.
- [ ] Read these from trunk at program start. Re-read them at every tick.
  - [ ] `git show origin/main:DESIGN.md`
  - [ ] `git show origin/main:docs/specs/README.md`
  - [ ] `git show origin/main:docs/specs/PLAN.md`
  - [ ] The pstack playbooks `autopilot-stack.md`, `opening-a-pr.md` and the `swarm` skill, from the plugin cache at `~/.claude/plugins/cache/pstack-local/pstack/0.15.2-cc.1/skills/`.
  - [ ] The `impeccable` skill before any design PR, and `unslop` before any prose.
- [ ] Arm the 30-minute audit tick as a `/loop` in this chat. Never leave the cadence to memory.
- [ ] Use this tick prompt, verbatim. "Re-read the execution playbook from trunk and the armed /goal. Audit the operation against both and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then post a status message to the operator in chat, whether or not anything changed, with the queue table of PR, owner, state, and head SHA, the verdicts since the last tick, what merged, open operator gates, and blockers."
- [ ] On the operator's hold or stand-down, send every owner a zero-writes order at once.

### Spawn owners

- [ ] The head owns all six phase 1 PRs. Verification lanes are `sonnet` subagents. Backend waves in `.claude/plans/backend-fixes.md` run in parallel under `intportal-backend` workers, and `00-sis-host` joins that chain right after W1b because both own `PortalController`.
- [ ] Follow this dependency graph.
  - [ ] P3 and F1 are independent and first. Both branch from `main` after the docs PR lands.
  - [ ] F2 after F1. F3 after F2 and after the P3 variant picks.
  - [ ] S1 after F3 and after backend W1d merges, since both edit `App/PUPSISPortalApp.swift`.
  - [ ] L1 after S1.
- [ ] Hold the file boundaries.
  - [ ] F1 touches only `Core/Theme.swift`, `Core/FontLibrary*`, `Resources/Fonts/`, `Package.swift`, `Scripts/shot.sh`, `Sources/PUPSISPortalApp/Debug/` and `Tests/PUPSISPortalTests/`.
  - [ ] F2 touches only `Views/Pixel/`, `Views/Quiz/QuizVisuals.swift`, `Debug/` and tests.
  - [ ] F3 touches only `Resources/Shaders/`, `Views/Depth/`, `Debug/` and tests.
  - [ ] S1 moves `ContentView` out of `App/PUPSISPortalApp.swift` into `Views/Shell/AppShell.swift` first, so backend workers and the shell never edit the same lines.
- [ ] Hold the review gate. P3, F2, F3, S1 and L1 change an interaction. They wait for the operator's review in chat with screenshots and a video before they land.

### PR mechanics, for every PR

- [ ] Resolve the forge once. `origin` is not installed here, so use `gh` against `cGradying/IntPortal` and record that fallback.
- [ ] Open the PR ready, never draft, with `gh pr create --base <base-branch>`. A stack child targets its parent branch.
- [ ] Run `swift build` and `swift test` once before the PR-facing push. Push with hooks on.
- [ ] Run `/deslop` before each commit and `/no-comments` before review. Commits carry no Claude co-author trailer (IntPortal rule).
- [ ] Triage every Bugbot and security-reviewer comment per `../references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before babysit and again before the merge-ready report.

### Verdict and merge, for every PR

- [ ] At the stack-ready head SHA, run the swarm per the `swarm` skill. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. One audit lane that reads the diff and the receipts and distrusts the PR body.
- [ ] Clean only when every lane is `PASS`. Findings go back to the owner. A new head gets a fresh swarm and a fresh verdict.
- [ ] A clean verdict appends the PR to the linear stack. The operator lands it bottom-up. After any rebase, compare `git patch-id` at the verdict SHA with the new diff, and send a changed patch back through the swarm per `playbooks/shipping.md`.

### Boot recipe, for every live lane

Each live lane runs locally in its own worktree at the PR head, since the surface is a native macOS app. Snapshot lanes run in parallel. Lanes that launch the real app take the mutex `mkdir /tmp/intportal-live.lock` and remove it on exit. P3 lanes drive the HTML prototype with the Playwright MCP tools.

- [ ] `git fetch origin <head-branch> && git worktree add ../IntPortal-wt/lane-<n> <head SHA>`.
- [ ] Snapshot lanes run `swift test --filter Snapshot` with `INTPORTAL_SNAPSHOT_DIR` set, which renders views to PNG through `ImageRenderer` at a fixed animation phase. Live lanes run `Scripts/make_mac_app.sh` in Debug, then `open IntPortal.app --args -IntPortalDemo -IntPortalScreen <screen>`. They wait for the window.
- [ ] Deliver input only through launch arguments, `osascript` keystrokes and `Scripts/shot.sh`. Read-only diagnostics are `log stream --predicate 'subsystem == "IntPortal"'`, `ps -o %cpu,rss` and the Metal HUD (`MTL_HUD_ENABLED=1`).
- [ ] Save every screenshot to `/tmp/swarm-<pr-id>/worker-<n>/<slug>.png` and return the paths with the report.

## Prototype the new 3D in HTML before native (P3)

**Depends on.** The docs PR.

**Files.**

- [ ] Create `docs/specs/prototypes/intportal-v3.html`, copied from `intportal-v2.html`.
- [ ] Edit `docs/specs/README.md` to point the reference build at v3.
- [ ] Create `Scripts/extract-js.mjs`, which prints a page's inline script blocks so `node --check` can parse them.

**Build.**

- [ ] Hub campus carousel. Portal frames stand on a ring you orbit with arrow keys. The lit frame is PUP SIS with the campus label, and locked frames are dark.
- [ ] Two competing versions of the Schedule week change, toggled with a `?turn=cube|slab` query. `cube` rotates the grid about Y. `slab` slides the week back in Z while the next one rises.
- [ ] Two competing versions of the screen change, toggled with `?depth=push|dive`. `push` moves along the sidebar's order in Z. `dive` runs a 180ms pixelate through a mini portal.
- [ ] Sync ripple from the sidebar glyph (green ring for a good sync, a red stutter for a failure). Deck fan-out whose fan width equals the due count. The IntAssis orb becomes a spinning voxel cube while it thinks.
- [ ] macOS 27 motion. Every transition is an interruptible spring. Floating layers get a darkened edge and a top highlight.
- [ ] Publish to the existing artifact URL as version 4.

**You see.**

- [ ] Pressing the right arrow on the hub turns the ring one frame in under 400ms, and Return warps into the lit frame.
- [ ] Clicking Refresh sends one ring out from the glyph that crosses every sheet and ends within 900ms.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `node --check` on the extracted script block passes. Run `node Scripts/extract-js.mjs docs/specs/prototypes/intportal-v3.html | node --check`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Load v2 and v3, skip the landing, and open Schedule. Save `trunk-v2.png` and `head-v3.png`. Pass when every v2 screen still exists in v3 with the same sheets.
- [ ] Lane 2. Orbit the hub ring three frames right and back. Save `orbit.png`. Pass when the lit frame returns to center and focus stays on it.
- [ ] Lane 3. Page Schedule forward with `?turn=cube`. Save `turn-cube.png` mid-turn. Pass when the next week's dates appear and the turn ends in under 500ms.
- [ ] Lane 4. Page Schedule forward with `?turn=slab`. Save `turn-slab.png` mid-turn. Pass when the next week's dates appear and the turn ends in under 500ms.
- [ ] Lane 5. Change screens Today to Grades with `?depth=push`, then `?depth=dive`. Save `depth-push.png` and `depth-dive.png`. Pass when each change ends in under 400ms and the header title updates.
- [ ] Lane 6. Trigger a good sync, then a failed sync. Save `ripple-ok.png` and `ripple-fail.png`. Pass when the colors differ and each ripple stops.
- [ ] Lane 7. Open a deck with 7 due, then one with 23 due. Save `fan-7.png` and `fan-23.png`. Pass when the second fan is visibly wider and the first card deals to center.
- [ ] Lane 8. Ask IntAssis a question. Save `orb-think.png`. Pass when the orb is a voxel cube while waiting and returns to the orb after the reply.
- [ ] Lane 9. Emulate `prefers-reduced-motion`. Repeat lanes 2 to 7. Save `reduced.png`. Pass when no element moves and every state still changes.
- [ ] Lane 10. Resize to 375 wide. Save `phone.png`. Pass when there is no horizontal scroll and the carousel stacks.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Frame time p95 during the warp and during a week turn, from `performance.now()` deltas.
- [ ] Probe. A Playwright script runs each animation five times at v2 and v3, interleaved.
- [ ] Baseline. Record the v2 warp p95 first. v2 has no week turn, so the turn gets an absolute budget.
- [ ] Rule. v3 warp p95 within 10 percent of v2. Week turn and screen change p95 under 16.7ms. Fail at either number.

**Review gate.** The operator reviews before merge.

- [ ] Copy lanes 2 to 8 screenshots into `docs/specs/reference/P3-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of both variants with Playwright video capture. Save it as `docs/specs/reference/P3-review.mp4`.
- [ ] Post the screenshots and the video in chat. The operator picks `cube` or `slab` and `push` or `dive`. Record the picks in DESIGN.md. Stop at stack-ready.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends P3 to the stack and the operator lands it.

## Add tokens, fonts, motion and the snapshot tool (F1)

**Depends on.** The docs PR.

**Files.**

- [ ] Edit `Sources/PUPSISPortalApp/Core/Theme.swift`.
- [ ] Create `Resources/Fonts/PixelifySans/` and `Resources/Fonts/SourceSans3/`, each with `OFL.txt`.
- [ ] Create `Sources/PUPSISPortalApp/Debug/DemoData.swift` and `Debug/SnapshotSupport.swift`, both compiled only under `DEBUG`.
- [ ] Create `Scripts/shot.sh`.
- [ ] Edit `Tests/PUPSISPortalTests/PreferencesTests.swift` and create `Tests/PUPSISPortalTests/SnapshotTests.swift`.

**Build.**

- [ ] `Palette` gains the DESIGN.md role set plus `registrar` and `registrarNight`, and `.auto` maps to them. Existing roles stay until S1, so old screens do not change.
- [ ] `enum Spacing` and `Typography.display(size:weight:)`, with the fonts registered through `FontLibrary`.
- [ ] `Motion` gains `thunk`, `flip`, `pop`, `portalForm`, `ignite`, `warp`, `sweep`, `orbit`, `turn`, `depthPush`, `ripple`, `fan` and `think`, tuned as fast interruptible springs. `island` stays until S1 deletes its callers.
- [ ] Add an environment value that ORs the system Reduce Motion with `Preferences.forceReducedMotion`. Today only SettingsView honors that setting.
- [ ] Add `-IntPortalDemo`, which loads the sample week, grades and decks from `DemoData` with no network and no Keychain. `-IntPortalScreen <name>` opens a screen.
- [ ] Add a snapshot helper that renders any view through `ImageRenderer` at a given scheme, UI scale and animation phase to `INTPORTAL_SNAPSHOT_DIR`.
- [ ] `Scripts/shot.sh <out.png>` finds the IntPortal window ID with `CGWindowListCopyWindowInfo` and runs `screencapture -l`.

**You see.**

- [ ] `swift test --filter Snapshot` writes `tokens-light.png` and `tokens-dark.png`, showing every Registrar role swatch and both fonts.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `MotionTests` asserts all 20 tokens return `nil` when reduced and non-nil otherwise, including `selection` and `drag`, which the current test skips. Run `swift test --filter MotionTests`.
- [ ] A test asserts that `forceReducedMotion = true` makes the environment value true with the system setting off. Run `swift test --filter ReduceMotionTests`.
- [ ] A test asserts `Palette.registrar.action` equals `#1B5DB8` and `menuField` equals `#6D0E1F`. Run `swift test --filter PaletteTests`.
- [ ] A test asserts a Release build compiles without `DemoData`. Run `swift build -c release`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Launch trunk and head with `-IntPortalScreen schedule` and compare the windows. Trunk has no demo mode, so gate that head matches trunk pixel for pixel outside the sample data. Save `trunk.png` and `head.png`. Pass when the diff shows only the data.
- [ ] Lane 2. Snapshot the token sheet in light. Save `tokens-light.png`. Pass when every swatch matches its DESIGN.md hex to within 1 per channel.
- [ ] Lane 3. Snapshot the token sheet in dark. Save `tokens-dark.png`. Pass when every swatch matches the Registrar Night hex to within 1 per channel.
- [ ] Lane 4. Snapshot display and body type at UI scale 80, 100 and 140. Save `type-scales.png`. Pass when Pixelify Sans and Source Sans 3 render (no fallback glyph shapes) at all three scales.
- [ ] Lane 5. Launch with `-IntPortalDemo`. Save `demo.png`. Pass when the sample week shows and `log stream` shows no request to `pup.edu.ph`.
- [ ] Lane 6. Turn on the in-app force-reduced-motion setting and open the Schedule week. Save `force-reduced.png`. Pass when block arrival is instant outside Settings too.
- [ ] Lane 7. Run `Scripts/shot.sh` twice in a row. Save `shot-a.png`. Pass when both files exist and show only the IntPortal window.
- [ ] Lane 8. Build Release and search the binary for `IntPortalDemo`. Save `release-strings.png` of the terminal. Pass when there is no match.
- [ ] Lane 9. Launch with every theme room. Save `rooms.png`. Pass when every room either fills every new role or is listed for removal in the PR body.
- [ ] Lane 10. Run the app 60 seconds idle with the window inactive. Save `idle.png` of `ps`. Pass when CPU averages under 1 percent.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Cold launch to first window, from a `log` signpost, plus idle CPU with the window inactive.
- [ ] Probe. Launch trunk and head five times each, interleaved, and read the signpost times and `ps -o %cpu`.
- [ ] Baseline. Record the trunk median launch time and idle CPU first.
- [ ] Rule. Head median launch within 50ms of trunk, since font registration is the only added work. Idle CPU within 0.5 points. Fail at either number.

**Review gate.** None. F1 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends F1 to the stack and the operator lands it.

## Build the pixel components and gallery (F2)

**Depends on.** F1.

**Files.**

- [ ] Create `Views/Pixel/PixelNotch.swift`, `PixelIcon.swift`, `Sheet.swift`, `PixelButtonStyle.swift`, `Stamp.swift` and `Dither.swift`.
- [ ] Create `Debug/ComponentGallery.swift`, opened with `-IntPortalScreen gallery`.
- [ ] Edit `Views/Quiz/QuizVisuals.swift` so `PixelBadge` calls `PixelIcon` drawing.

**Build.**

- [ ] Every component in spec 01's New files list, with the prototype's icon bitmaps copied into `PixelIcon.Glyph` by a script (`Scripts/icons-from-prototype.mjs`) rather than by hand.
- [ ] Stamp plays `thunk`, and its ink mask is generated once and cached.
- [ ] Buttons and sheets take the macOS 27 depth treatment only when floating (a darkened edge and top highlight).

**You see.**

- [ ] The gallery shows every component in both themes, and clicking a stamp replays the thunk.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `PixelNotchTests` asserts the eight corner points for a 100 by 40 rect. Run `swift test --filter PixelNotchTests`.
- [ ] `PixelIconTests` asserts the `today` glyph has the prototype's on-cell count. Run `swift test --filter PixelIconTests`.
- [ ] Running `Scripts/icons-from-prototype.mjs` again leaves `git diff` empty.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Open the Quiz screen on trunk and head. Save `quiz-trunk.png` and `quiz-head.png`. Pass when `PixelBadge` looks the same.
- [ ] Lane 2. Snapshot the gallery in light. Save `gallery-light.png`. Pass when no component shows a rounded corner.
- [ ] Lane 3. Snapshot the gallery in dark. Save `gallery-dark.png`. Pass when text contrast on every sheet is at least 4.5 to 1.
- [ ] Lane 4. Snapshot every icon at 12 and 24. Save `icons.png`. Pass when the edges are crisp at integer scale with no antialiasing.
- [ ] Lane 5. Click each stamp in the live gallery. Save `stamp-mid.png` mid-thunk. Pass when the thunk ends in 420ms plus or minus 40ms.
- [ ] Lane 6. Tab through the gallery. Save `focus.png`. Pass when every control shows the inset 2pt action ring.
- [ ] Lane 7. Run VoiceOver over the gallery buttons. Save `vo.png` of the caption panel. Pass when every icon-only button reads a label.
- [ ] Lane 8. Turn on Reduce Motion and click a stamp. Save `stamp-reduced.png`. Pass when the stamp appears with no scale or blur.
- [ ] Lane 9. Snapshot at UI scale 80 and 140. Save `gallery-scales.png`. Pass when nothing clips.
- [ ] Lane 10. Snapshot the floating sheet sample. Save `float.png`. Pass when it has the dark edge and top highlight and inline sheets do not.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Gallery render time for one frame with 200 stamps, plus quiz screen first frame at trunk and head.
- [ ] Probe. A snapshot test times `ImageRenderer` over ten runs at trunk and head, interleaved, for the quiz screen, and at head for the gallery.
- [ ] Baseline. Record the trunk quiz screen median first.
- [ ] Rule. Quiz median within 10 percent of trunk. Gallery with 200 stamps under 16ms, which proves the cached ink mask. Fail at either number.

**Review gate.** The operator reviews before merge.

- [ ] Copy lanes 2, 3 and 5 screenshots into `docs/specs/reference/F2-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of the gallery with `screencapture -v`. Save it as `docs/specs/reference/F2-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at stack-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends F2 to the stack and the operator lands it.

## Build the depth kit, shaders and 3D modifiers (F3)

**Depends on.** F2 and the P3 variant picks.

**Files.**

- [ ] Create `Resources/Shaders/Portal.metal` (`portalSwirl`, `pixelate`) and `Resources/Shaders/Ripple.metal` (`syncRipple`).
- [ ] Edit `Package.swift` to add `.process("Resources/Shaders")`.
- [ ] Create `Views/Depth/OrbitRing.swift`, `WeekTurn.swift`, `DepthPush.swift`, `SyncRipple.swift`, `DeckFan.swift` and `VoxelOrb.swift`.
- [ ] Edit `Debug/ComponentGallery.swift` to add a Depth page.

**Build.**

- [ ] The shader source from spec 09, plus `syncRipple(position, layer, origin, time, ok)`, called through `ShaderLibrary.bundle(.module)`.
- [ ] Each 3D modifier is a pure function of one progress value from 0 to 1. `OrbitRing(index:)`, `WeekTurn` in the picked variant, `DepthPush(direction:)` in the picked variant, `DeckFan(count:)`, `VoxelOrb(thinking:)`. Every one reads its `Motion` token and becomes a crossfade under Reduce Motion.
- [ ] A Metal-unavailable fallback draws the static swirl frame through `Canvas`.

**You see.**

- [ ] The gallery's Depth page plays each effect, with a slider that scrubs its progress value.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `DepthMathTests` asserts `DeckFan` angles for 1, 7 and 23 cards and `OrbitRing` positions for 3 frames at index 0 and 1 against literal values. Run `swift test --filter DepthMathTests`.
- [ ] `ShaderLoadTests` asserts both shader functions resolve from the bundle. Run `swift test --filter ShaderLoadTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Trunk has no shaders, so record that and gate that the head app launches with the shader library loaded. Save `head-launch.png`. Pass when the log shows no shader error.
- [ ] Lane 2. Snapshot the swirl at progress 0, 0.5 and 1. Save `swirl.png`. Pass when the five ramp colors appear and cells are square.
- [ ] Lane 3. Scrub `OrbitRing` from 0 to 1. Save `orbit.png`. Pass when the center frame is largest and others recede.
- [ ] Lane 4. Scrub `WeekTurn`. Save `turn.png`. Pass when both weeks are visible at 0.5 and there is no gap between faces.
- [ ] Lane 5. Scrub `DepthPush` both directions. Save `push.png`. Pass when forward and back mirror each other.
- [ ] Lane 6. Play `SyncRipple` ok and fail. Save `ripple.png`. Pass when the ring leaves from the origin and ends at the window edge.
- [ ] Lane 7. Snapshot `DeckFan` at 1, 7 and 23. Save `fan.png`. Pass when the fan width grows with count.
- [ ] Lane 8. Play `VoxelOrb` thinking then idle. Save `orb.png`. Pass when it returns to the orb shape.
- [ ] Lane 9. Turn on Reduce Motion and play every effect. Save `depth-reduced.png`. Pass when every effect is a crossfade of 200ms or less.
- [ ] Lane 10. Force the Metal fallback with `-IntPortalNoMetal`. Save `fallback.png`. Pass when the static frame shows and nothing crashes.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Frame rate from the Metal HUD while each effect loops, plus GPU time for one swirl frame at 1440 by 900.
- [ ] Probe. Loop each effect for 10 seconds with `MTL_HUD_ENABLED=1` and read the HUD. Trunk has no effects, so measure trunk idle and head idle interleaved.
- [ ] Baseline. Record trunk idle frame rate and CPU first.
- [ ] Rule. Every effect holds 60 fps or better on a 60Hz display. Swirl GPU time under 2ms. Head idle CPU within 0.5 points of trunk. Fail at any number.

**Review gate.** The operator reviews before merge.

- [ ] Copy lanes 2 to 8 screenshots into `docs/specs/reference/F3-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of the Depth page with `screencapture -v`. Save it as `docs/specs/reference/F3-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at stack-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends F3 to the stack and the operator lands it.

## Replace the nav island with the sidebar shell (S1)

**Depends on.** F3 and backend W1d.

**Files.**

- [ ] Create `Views/Shell/AppShell.swift`, `Sidebar.swift`, `ScreenHeader.swift` and `PortalGlyph.swift`.
- [ ] Edit `App/PUPSISPortalApp.swift` for commands and the `ContentView` move only.
- [ ] Delete `Views/NavIsland.swift`, `Views/HomeNoiseField.swift`, `Views/DitherFill.swift` and `Views/WindowChrome.swift`.

**Build.**

- [ ] Spec 01 in full. Sidebar, header, destinations, ⌘0 to ⌘6, Settings as a screen, and the old `Typography` roles routed to the new faces.
- [ ] Screen changes use `DepthPush` along the sidebar's order.
- [ ] Refresh plays `SyncRipple` from `PortalGlyph`, green on success and red on failure.
- [ ] Remove `Motion.island` and migrate its 9 callers in the same PR.

**You see.**

- [ ] ⌘3 from Today pushes forward into Grades, and ⌘R ripples out from the glyph.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `DestinationTests` asserts each shortcut maps to its destination and the depth direction. Run `swift test --filter DestinationTests`.
- [ ] `grep -rn "RoundedRectangle\|glassEffect" Sources/PUPSISPortalApp/Views` prints nothing.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Press ⌘1, ⌘2 and ⌘3 on trunk and head in demo data. Save `nav-trunk.png` and `nav-head.png`. Pass when each shortcut reaches the same content (⌘2 is now Today, as spec 01 says).
- [ ] Lane 2. Click every sidebar item. Save `sidebar.png`. Pass when every screen opens and the active item is marked.
- [ ] Lane 3. Press ⌘4, ⌘5, ⌘6 and ⌘,. Save `shortcuts.png`. Pass when Notebook, Quizzes, Syllabus and Settings open.
- [ ] Lane 4. Go Today to Syllabus and back. Save `push.png` mid-change. Pass when forward and back move in opposite directions.
- [ ] Lane 5. Press ⌘R with demo success, then with `-IntPortalDemoFail`. Save `ripple-ok.png` and `ripple-fail.png`. Pass when the glyph line reads "Couldn't reach SIS · Try again" on failure.
- [ ] Lane 6. Set UI scale 80 and 140. Save `scales.png`. Pass when the sidebar and header stay intact.
- [ ] Lane 7. Turn on Reduce Motion and change screens. Save `reduced.png`. Pass when there is no transition and the glyph is static.
- [ ] Lane 8. Make the window inactive for 30 seconds. Save `inactive.png` of `ps`. Pass when CPU averages under 1 percent and the glyph is paused.
- [ ] Lane 9. Run VoiceOver over the sidebar. Save `vo.png`. Pass when the current item reads as selected.
- [ ] Lane 10. Snapshot every screen in Registrar and Registrar Night. Save `themes.png`. Pass when no view shows an old nav island or glass.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Time from ⌘ shortcut to the new screen's first frame, plus idle CPU with the window inactive.
- [ ] Probe. An `osascript` loop presses ⌘1 to ⌘3 twenty times at trunk and head, interleaved, reading signposts.
- [ ] Baseline. Record the trunk median switch time first.
- [ ] Rule. Head median switch time under trunk plus 60ms, which covers the depth push. Idle CPU within 0.5 points. Fail at either number.

**Review gate.** The operator reviews before merge.

- [ ] Copy lanes 2, 4, 5 and 10 screenshots into `docs/specs/reference/S1-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of navigation with `screencapture -v`. Save it as `docs/specs/reference/S1-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at stack-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends S1 to the stack and the operator lands it.

## Build the portal landing and hub carousel (L1)

**Depends on.** S1.

**Files.**

- [ ] Create `Core/LandingSequence.swift` and `Views/Landing/PortalLanding.swift`, `PortalHub.swift` and `SignInPanel.swift`.
- [ ] Delete `Views/CredentialsView.swift` once `SignInPanel` covers its behavior.
- [ ] Edit `Views/Shell/AppShell.swift` to overlay the landing.

**Build.**

- [ ] Spec 09 in full. `LandingSequence` is a pure state machine over `LandingPhase`, driven by one clock, so snapshots can pin any phase.
- [ ] The hub uses `OrbitRing` with PUP SIS lit and the locked frames dark. Arrow keys orbit and Return warps.
- [ ] Sign-in keeps the current copy "Login now" and "Locked in your Mac's Keychain. This portal only ever talks to PUP SIS."

**You see.**

- [ ] A signed-in launch lands with the portal humming, and one Return warps into Today.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `LandingSequenceTests` asserts the phase at t = 0.2, 1.0, 1.9 and 2.5, the warp end at 1.08s, and 0.22s under Reduce Motion. Run `swift test --filter LandingSequenceTests`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `sonnet` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Launch signed out on trunk and head. Save `signin-trunk.png` and `signin-head.png`. Pass when the same fields exist and the copy matches.
- [ ] Lane 2. Snapshot each landing phase. Save `phases.png`. Pass when void, forming, ignite, sign in and hub each match the prototype's layout.
- [ ] Lane 3. Launch signed in with demo data and press Return. Save `warp-flash.png` at 82 percent. Pass when the app shows Today within 1.2s.
- [ ] Lane 4. Orbit the hub left and right. Save `hub-orbit.png`. Pass when locked frames cannot be entered and read "Not connected yet".
- [ ] Lane 5. Type a student number ending in `-MN-0`. Save `campus.png`. Pass when the chip reads "MN · Sta. Mesa".
- [ ] Lane 6. Press Return during the forming phase. Save `skip.png`. Pass when the beat skips to sign in.
- [ ] Lane 7. Turn on Reduce Motion and launch. Save `reduced.png`. Pass when the swirl is static and the warp is a 200ms crossfade.
- [ ] Lane 8. Launch offline with `-IntPortalDemoOffline`. Save `offline.png`. Pass when the offline state from spec 09 shows.
- [ ] Lane 9. Launch with `-IntPortalNoMetal`. Save `nometal.png`. Pass when the fallback frame shows and sign-in works.
- [ ] Lane 10. Turn off "Play portal intro" in Settings and relaunch. Save `nointro.png`. Pass when the app opens straight to Today.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Signed-in launch to the first interactive Today frame, and frame rate during the warp.
- [ ] Probe. Five signed-in demo launches at trunk and head, interleaved, reading signposts and the Metal HUD.
- [ ] Baseline. Record the trunk median launch-to-schedule time first.
- [ ] Rule. With the intro skipped by Return at the hub, head is within 150ms of trunk. With the intro off, head is within 50ms. The warp holds 60 fps. Fail at any number.

**Review gate.** The operator reviews before merge.

- [ ] Copy lanes 2 to 5 screenshots into `docs/specs/reference/L1-review-<slug>.png`.
- [ ] Record a 30 to 60 second video of a full launch and warp with `screencapture -v`. Save it as `docs/specs/reference/L1-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at stack-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends L1 to the stack and the operator lands it.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Write `docs/specs/PLAN-2.md` in this format for the worker phase. It covers C1 campus (10), SC schedule with `WeekTurn` (03), T today and notebook (04), G grades (05), ST study with `DeckFan` (11), AS assistant with `VoxelOrb` (06), SE settings (07), MB menu bar (08) and HF, the HyperFrames trailer rendered from `intportal-v3.html` into `docs/media/trailer.mp4` and the README. Owners there are `pstack:poteto-agent` on `sonnet`.
- [ ] Reply to the operator with the autopilot-stack report, which is the stack root and tip links, a one-line verdict per PR, and anything parked.

## Appendix A. Prototype evidence

- The v2 prototype (`docs/specs/prototypes/intportal-v2.html`, artifact EDhhji1pkGZKorG6464MPm version 3) proved the landing sequence, the swirl palette and the pixel system. The operator approved it on 2026-09-23.
- Unproven until P3 lands are the week turn variant, the screen change variant, and whether the ripple reads as sync rather than decoration. P3 builds two variants for each contested move, and the operator picks.
- Unproven until F1 lands is whether `ImageRenderer` renders `layerEffect` shaders. If it does not, shader lanes move to live capture with `Scripts/shot.sh`.

## Appendix B. Alternatives rejected

- RealityKit gives real meshes and lighting but needs a macOS 15 minimum and costs memory. SceneKit is deprecated.
- three.js in a WKWebView reuses the prototype code but adds JS startup, memory and a bridge for every 3D element.
- HyperFrames for in-app video was rejected because a pre-rendered warp cannot show the campus or sync state and adds megabytes. It stays for the trailer.
- Liquid Glass chrome, which is the macOS 27 default, was rejected by the operator in favor of 27's motion and depth on pixel sheets.
- Grades towers were offered and not picked.
- Planning all 14 PRs in full now was rejected. Screen slices depend on the primitives F1 to F3 settle, so they are planned in PLAN-2 once L1 is ready.

## Appendix C. Risks

- The Metal toolchain download may fail or need an Xcode update. It blocks every PR. The head checks `xcodebuild -showComponent MetalToolchain` first.
- `Scripts/shot.sh` and `screencapture -v` need Screen Recording permission for the terminal. The operator grants it once in System Settings, because the head never changes security settings.
- S1 and backend W1b to W1d both edit `App/PUPSISPortalApp.swift`. S1 waits for W1d and moves `ContentView` out first.
- Demo mode must never ship. F1 lane 8 and the Release build check guard it.
- No control skill exists for native macOS apps here. Live lanes drive the app through launch arguments, `osascript` and `Scripts/shot.sh`, and live lanes share one mutex.
- Theme rooms that cannot fill the new roles are removed (DESIGN.md). F1 lane 9 lists them, and S1 removes them.

## Appendix D. Links and reading list

- Read `DESIGN.md`, `CONTEXT.md`, `docs/specs/README.md`, spec 01 and spec 09 before editing.
- F3 and L1 get the `how` skill before building and `interrogate` before stack-ready, since the shader and the state machine are the riskiest code.
- Keep a `decisions.tsv` trail per the `show-me-your-work` skill in `.claude/plans/trail/`, uncommitted.
- Backend program is `.claude/plans/backend-fixes.md`. Handoff log is `.claude/plans/ui-revision-spec-plan.md`.
