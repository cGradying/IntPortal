# Changelog

What changed in each release of IntPortal for macOS, newest first, from the commit history. Releases with their downloads are on [GitHub Releases](https://github.com/cGradying/IntPortal/releases).

IntPortal for macOS is in maintenance; new work happens in the phone app, [cGradying/intportal-app](https://github.com/cGradying/intportal-app).

## Unreleased (on `main` after 1.6.8)

- perf(landing): hub at rest from 28.5% to 9% CPU (Debug, demo)
- feat(landing): portal landing, hub ring and warp replace the login screen
- fix(shell): start sign-in from the shell and show a failed sign-in in the sidebar
- feat(shell): maroon sidebar shell replaces the nav island
- wip: sidebar shell
- fix(session): grade-history resilience, reauth, keychain-save, notifier sync
- fix(assistant): disambiguate move_event by start, guard execute against cancellation
- fix(calendar): document what a skipped-DST-hour nil means per caller
- fix(sis): degrade an unmatched sign-in marker to a delay, not a failure
- fix(calendar): route DST elapsed-minutes bug through one wall-clock helper
- fix(sis): re-authenticate on refresh when the SIS session expired
- fix(calendar): fix stale export duplicates, missing resync keys, vacant-week reminders
- fix(grades): quarantine corrupt grades/schedule caches instead of clobbering them
- fix(assistant): stop Auto-mode side effects on cancel, close note-exclusion and tag-injection gaps
- fix(ai): async stop(), key off argv, explicit loopback host (W8 round 2)
- fix(session): every navigation waits for the sign-out clear; chain clears
- fix(session): make sign-out synchronous, sign-in wait for the website-data clear
- fix(ai): harden local model runtime against orphaned/foreign servers (W8)
- fix(assistant): stop stale turns writing back, fix cloud-provider gaps, notes leak
- fix(auth): make GoogleTokenStore injectable so tests never touch the real Keychain
- fix(auth): treat invalid_grant refresh as disconnected, don't hang on session start failure
- fix(session): clear website data on sign-out, no-op refresh, SIS host failover
- fix(calendar): undo falls back when an occurrence's identifier drifts
- fix(prefs): utcCalendar never reassigned, declare it let not var
- fix(prefs): migrate legacy week keys via zone-independent Monday recovery
- fix(schedule): keep positional pairing for a joined day run with one range per day
- fix(schedule): repeat a lone day/range group across the other side's groups
- fix(calendar): undo matches occurrences by identifier, not slot/title
- fix(session): make sign-in/refresh single-flight and sign-out-safe
- fix(prefs): key week overrides by calendar day, not local-midnight epoch
- fix(schedule): pair days to times per slash-group, dedupe id collisions
- fix(stores): quarantine corrupt files instead of overwriting them
- feat(depth): cube week turn and depth push screen change
- feat(depth): portal shaders, swirl, orbit ring, deck fan, thinking cube, sync ripple
- feat(pixel): notch, icons, sheet, buttons, stamp, gallery
- feat(theme): Registrar tokens, design fonts, motion set, demo mode

## 1.6.8 (2026-09-24)

- docs(design): the Legibility Rule, small numbers in Source Sans 3
- docs(design): record P3 picks, cube week turn and push screen change
- docs(prototype): v3 with hub carousel, week turn, depth change, sync ripple, deck fan, thinking cube
- docs(specs): UI revision specs, DESIGN.md rewrite, 3D motion plan

## 1.6.7 (2026-09-05)

- fix(calendar): dither as a halo ring, not a backing wash
- fix(calendar): invert today's text/dot color over the dither wash
- fix(calendar): today marker is a dither wash, not a rule
- fix(schedule): parse trailing faculty text after times; wire RAG token budget; today = dither underline
- fix(sis): revert to sis8, drop session-skip fast path
- perf(portal): reuse session before re-authenticating
- feat(settings): pixel-dither language, collapsible sections, 8 famous themes

## 1.6.6 (2026-09-01)

- feat(syllabus): import/generate, AI extraction, review, calendar export, quiz generation, grading calculator
- test(ai): add real-hardware MLX generation smoke test
- feat(notes): reading-width + sidebar-side settings, typography pass
- fix(ui): strip markdown syntax from assistant reveal text, restore orb padding
- fix(quiz): use the local MLX client for generation and explanations
- fix(ai): enable the MLX model path end to end
- fix(sis): migrate SIS base URL from sis8 to sis1
- feat(settings): compact custom shell, Data & Storage, Advanced AI Tuning, Reset
- refactor(settings): sidebar shell, Data & Storage pane, Advanced AI tuning
- fix(ai): quantize KV cache, reserve real output budgets, no model swap
- fix(notes): "Ask AI" empty response — the real cause was reasoning, not length
- fix(notes): "Ask AI" pill (Structure/Summarize/Answer) returns empty on long notes
- fix(assistant): tool-calling breaks at low context, unbounded at high
- refactor(settings): compact the Appearance tab
- feat(ai): bring-your-own-key providers — OpenAI, Google, Anthropic
- feat(syllabus): assistant tools for reading and building a syllabus
- feat(syllabus): SyllabusView — table + timeline, two entry points
- feat(syllabus): all-day markers on the week header + Today timeline
- fix(notes): markdown from outside a fenced code block leaking inside it
- feat(syllabus): SyllabusStore — the schema every syllabus ticket builds on
- feat(notes): typography pass — measure, line-height, heading scale, code block
- feat(notes): toolbar deck wraps to 2 rows instead of overflowing
- feat(assistant): hover rail for cross-page quick actions
- fix(notes): heading (and every other) mark stayed visible on first load
- fix(notes): deck sizing, expand/compress morph, formatting shortcuts
- feat(notes): merge AI orb + note toolbar into one floating deck
- fix(notes): editable title, hide inline markdown syntax markers

## 1.6.5 (2026-08-28)

- chore: trailing whitespace cleanup in Log-in UI.swift, gitignore .vscode/
- feat(dev): wire in Inject for hot reload during dev builds
- fix(ui): sliders instead of steppers for RAG chunk/context tuning; catchier login footer
- feat(ai): live RAM estimate next to context-size slider

## 1.6.4 (2026-08-27)

- fix(ci): correct SSL flag name + disable GGML_NATIVE for x86_64 cross-compile

## 1.6.3 (2026-08-27)

- fix(ci): force LLAMA_SERVER_SSL off in universal llama-server build

## 1.6.2 (2026-08-27)

- feat(ai): standalone -with-AI dmg — bundle llama-server + Qwen3/nomic weights

## 1.6.1 (2026-08-27)

- Release build only.

## 1.6.0 (2026-08-27)

- feat(ai): context-size slider for local model, ctx-size wired to llama-server

## 1.5.9 (2026-08-27)

- fix(ui): quiz screens join UI Scale, semantic colors, Notebook labels
- polish: dead code cleanup, quiz auto-advance respects Reduce Motion
- fix(ui): Settings matches the app's own accent, month-dots respect the term
- fix(login): reassurance at credential entry, a way back after rejection
- fix(a11y): contrast fixes confirmed live, real labels on primary nav/quiz
- fix(ui): UI Scale now actually reaches the week grid and event popover
- feat(schedule): custom events in the monthly popup's dots, bigger panel
- fix(schedule): calendar popup sizes to content, blur reaches behind the island
- fix(schedule): floating calendar bigger/spacier, blur covers whole screen
- feat(schedule): floating calendar shows 4 months, not 12
- fix(schedule): fade the sidebar's top edge instead of a hard cutoff
- fix(ui): fade the top chrome band instead of a hard cutoff
- feat(schedule): resizable sidebar (status/syllabus/files) + floating month calendar
- fix(notebook): empty-day caption legible, not hidden behind a dither veil
- feat(assistant): name it IntAssis, warning only at chat start, reply reveal
- fix(ui): crisp text at every UI Scale level, no root scaleEffect
- fix(ui): kill the focused-window accent strip; close the AI structure/create markdown fence
- feat(calendar): a click on a custom event opens its editor, not just double-click

## 1.5.8 (2026-08-26)

- feat(calendar): description and link fields on custom events

## 1.5.7 (2026-08-26)

- feat(assistant): the model now knows today's date/time, and the whole term's schedule

## 1.5.6 (2026-08-26)

- chore(assistant): drop LFM2.5-2.6B from the model catalog

## 1.5.5 (2026-08-26)

- feat(assistant): swap Granite/Ollama for llama.cpp + Qwen3-1.7B

## 1.5.4 (2026-08-26)

- fix(assistant): ensureServerRunning gate applied even when RAG answers via Ollama
- feat(assistant): migrate to IBM Granite 4.2 — chat + RAG in one model

## 1.5.3 (2026-08-26)

- fix(build): every packaged release since v1.3.0 crashed on launch

## 1.5.2 (2026-08-26)

- feat(assistant): deterministic slash commands for the new calendar tools

## 1.5.1 (2026-08-26)

- ci: chain auto-release into mac-release via workflow_call, not tag push
- docs: note the empty-commit and self-referential-phrase gotchas in auto-release.yml
- test: verify auto-release fires on a normal merge to main
- ci: auto-tag a release on every merge to main

## 1.5.0 (2026-08-26)

- feat(assistant): capabilities popover, driven by the tool catalog
- feat(assistant): calendar date summaries + structured schedule edits

## 1.4.1 (2026-08-25)

- chore: rename GitHub repo cGradying/PUPSISPortal -> cGradying/IntPortal

## 1.4.0 (2026-08-25)

- feat(ci): sign, zip, and appcast releases for Sparkle auto-update
- feat(update): in-app auto-update via Sparkle 2

## 1.3.0 (2026-08-25)

- feat(ui): bundled Google Fonts library, glitch-text login hero, redesigned login screen
- feat(quiz): flashcard quiz mode with FSRS scheduling, UI scale setting
- feat(ui): three new themes, animated home background, class descriptions, README showcase

## 1.2.1 (2026-08-17)

- fix(ui): kill Today screen seams, resizable assistant panel, pixel-art polish (v1.2.1)
- Bug#1.1

## 1.2.0 (2026-08-17)

- test(assistant): stop 3 RAG tests depending on a real local llama-server
- feat(assistant): notes RAG, /rag command, Settings Misc tab, reveal-animation fixes
- fix(assistant): quit-time cleanup never actually ran
- feat(assistant): memory check before loading, kill AI on quit
- feat(assistant): ask_notes tool, grounded answers via llama.cpp
- feat(calendar): print/export the week as PDF
- fix(assistant): code blocks silently dropped from AI-written notes
- feat(calendar): per-class time overrides (this week / every week)
- feat(calendar): per-class description + online link
- feat(assistant): search over notes + user-editable house-style instructions
- fix(assistant): orb/panel never re-rendered on its own state change
- feat(assistant): floating orb + chat panel (Phase 2), permission setting (Phase 4), model-switch unload
- feat(assistant): wire tools to real stores, drop the toolbar draft button (Phase 2 prep + Phase 3)
- feat(assistant): engine layer for the local AI assistant (Phase 1)
- feat(notes): draft with a local model via Ollama
- feat: update nudge, release automation, note-image cleanup
- docs(windows): update status to reflect the confirmed-green CI build
- ci(windows): test the project directly, not the .slnx — confirmed WinUI build itself is green
- fix(windows): real fix for the PriGen MSB4062 — EnableMsixTooling + msbuild, not a guess
- ci(windows): pin the SDK windows-latest resolves to, without touching mac
- fix(windows): first CI build errors — Path ambiguity + IBuffer.ToArray()
- ci(windows): add a Windows build workflow
- chore(windows): Phase A3 static sweep — start the update check concurrently with sign-in, not after
- feat(windows): in-app update nudge
- fix(windows): notes editor no longer inlines the 1.9MB bundle into NavigateToString
- docs(windows): Stage 0-9 state audit table + known-bug/scope-cut summary
- docs(windows): detailed step-by-step Windows build/run walkthrough
- docs: update README for v1.1.2 — release history, license, Windows port status

## 1.1.2 (2026-08-14)

- chore: bump version to 1.1.2
- fix: drag-to-create-event no longer drags the whole window
- feat(windows): notes, grades, integrations, packaging (Stages 6-9)
- feat(windows): scaffold WinUI app — WebView2 driver, PasswordVault, calendar (Stages 3-5)
- feat(windows): port SIS session/scrape orchestration behind ISisWebView (Stage 2)
- feat(windows): port Preferences, GoogleCalendarClient, ICSExporter, Markdown (Stage 1g+1h)
- feat(windows): port stores + shared JsonStore helper (Stage 1f)
- feat(windows): port DayBlock, DayAgenda, NextClass, ClassRecurrence to C# (Stage 1e)
- feat(windows): port GradesParser + grade models to C# (Stage 1c)
- feat(windows): port GridGeometry, TimeSnap, MonthLayout to C# (Stage 1d)
- feat(windows): port Weekday, ClassSession, ScheduleParser to C# (Stage 1a+1b)
- feat(windows): scaffold C#/.NET Core library + tests for the WinUI port
- chore: stop listing local-only tooling in tracked .gitignore
- license: switch to PolyForm Noncommercial 1.0.0

## 1.1.1 (2026-08-13)

- feat: window chrome, nav island, dither band + MIT license (v1.1.1)

## 1.1 (2026-08-12)

- feat: notes rich editor — tables, images, color, dated class history (v1.1)

## 0.1.0-alpha (2026-08-12)

- feat: web notes editor (CodeMirror + KaTeX), note tabs, and fixes
- docs: release history, version, architecture gaps, future plans
- docs: full README — use cases, app walkthrough, and setup
- feat: direct Google Calendar export via OAuth + Calendar API
- feat: popup notes style with Obsidian-style Markdown
- feat: Google-via-EventKit UX, .ics export, custom events + free time in Today, and a Notes panel
- fix: gate glass on macOS 26 SDK marker, not toolchain version
- fix: compile-time gate the glass branch for older Xcode SDKs
- fix: build and run on macOS 14+, not just macOS 26
- feat: collapse the schedule controls behind an expanding icon
- feat: replace the sidebar with a floating dynamic-island switcher
- feat: cleaner sidebar — wordmark, roomier rows, Settings pinned bottom
- fix: make the signing-identity script work with OpenSSL 3
- feat: today agenda, GPA trend, menu-bar mini-agenda, ivory theme, login item
- fix: route each week's class to the calendar matching that week's status
- feat: route online classes to their own calendar; show vacant by default
- feat: remove vacant class occurrences from the exported calendar
- docs: vacant hides from grid, export auto-syncs on term status
- feat: auto-sync the export on status change, hide vacant classes
- docs: note online/vacant status in the exported calendar
- feat: reflect online/vacant status in the exported calendar
- docs: per-week status, online strips, and Today mode as the next plate
- feat: per-week class status, with an all-term toggle and online strips
- docs: add the menu bar to the feature catalog
- feat: menu bar presence with the next class at a glance
- docs: add the Grades feature to the catalog
- feat: grades page with a computed, weighted GPA
- docs: catalog shipped features for later GitHub docs
- feat: remind before class, and say what's next
- feat: connect multi-day blocks, and fix deleting a selection
- feat: rebuild event creation and editing around one grid-wide gesture layer
- feat: date the week grid, add a year view, and sync with Calendar.app
- feat: rebuild the interface on macOS 26, with themes and per-class editing
- feat: cache the schedule and stop the SIS races from hiding it
- Detect sign-in by polling the DOM, not by URL
- Rebuild around a native weekly calendar
- Fix double sign-in race that broke login + tabs
- Initial commit: PUPSISPortal

