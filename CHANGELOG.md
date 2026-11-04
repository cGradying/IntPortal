# Changelog

What changed in each release, newest first. A release PR adds its section; `scripts/version.sh` sets the version.

## 0.1.8 (2026-10-26)

- ai: Qwen3 1.7B is the default chat model; existing Gemma installs get an Update IntAssis button (1.1 GB chat model + 310 MB note search, use Wi-Fi) (#174)
- ai: note search uses EmbeddingGemma-2, on a llama.cpp bump (#173)
- ai: LAR refuses off-topic, prompt-leak, homework and harmful questions in its own voice; self-harm replies point to the NCMH hotline, 1553 or 0917-899-8727 (#177, #185)
- ai: LAR talks like a person; chit-chat answers instantly (#166, #177)
- ai: due-date answers cover overdue, eMabini and this week; reminders ask for notification permission; download sizes itemised (#182)
- ai: Filipino questions answered in Filipino (eval: Qwen 18/24, Gemma 21/24) (#183)
- ai: says "I don't have that" instead of inventing; near-miss questions invented 0 of 12 with retrieval (#150, #183)
- ai: cards from notes or a PDF honour the requested count, with a preview (#163)

Known gaps:

- Qwen's Filipino is garbled in about 1 reply in 4
- Chat source chips are not restored after relaunch (#180)
- Not yet run on a real phone with Qwen + EmbeddingGemma-2; speed and memory unverified. Check on a real iPhone and Android phone before wide rollout
- The in-app model download was only simulated by placing the files
- The engine is pinned to an unreleased upstream llama.cpp commit (cb98c630)

## 0.1.7 (2026-10-22)

- Portal hub: about 100 schools from the core, searchable sheet with recent, region and A–Z; far picks warp the orbit (#153)
- LAR chat: floating cube orb, fire spawn when it opens, pixel night sheet (#154)
- Launch on the void, not white; portal canvas resizes a frame after the observer fires (#155)
- Hub says when nothing matches; a demo sign-in shows SIS on the carousel; LAR's status no longer wraps (#155)

## 0.1.6 (2026-10-15)

- LAR: pixel sprite in each university's colours, fire spawn, wandering, orbit carousel (#140)
- ui: portal variety and the swipeable carousel (#124)
- ui: the landing's tile portal in Rust, compiled to WebAssembly (#117)
- Landing sign-in: floating-label fields, Show/Hide toggle, field error states (#140)

## 0.1.5 (2026-10-15)

- docs: README for 0.1.4, FEATURES.md, LICENSE, ARCHITECTURE for portals (#145)
- ui: AI cards from a PDF in a deck (#139)
- assis: PDF size, type, no-text and error messages (#139)
- ai: note chips answer from the open note, no blocking AI commands (#136)
- ui: LAR reminders survive sync, cards preview before saving (#135)
- release: one script sets the version everywhere; CHANGELOG from 0.1.0 (#134)
- ci(ios): add the wasm32 target, needed by the tile portal build (#117)

## 0.1.4 (2026-10-15)

- docs+ci: working in parallel; fix iOS Info.plist conflict markers (#127)
- ui: source chips open decks and subjects, Stop fixes (#125)
- ai: fix five bugs found by the test pass (#123)
- ai: Taglish open-question eval (#122)
- test: AI routing, replies and note modes (#121)
- test: IntAssis chat store and note-apply flows (#120)
- ui: AI cards from a note or PDF in a deck (#118)
- ai: index deck cards and syllabus for RAG (#119)
- IntAssis UI: streaming chat, sources, Ask AI in a note, Light or With AI at first run (#116)
- IntAssis: ai_note, Ask AI inside a note (#115)
- IntAssis: subject-aware grades, plain-language errors (#114)
- IntAssis: streamed replies and a chat that survives restarts (#113)
- IntAssis: notes reach the answers (RAG wired into ai_ask) (#112)
- IntAssis: Why? after a wrong answer, and the chat sheet fits above the keyboard (#111)
- ui: open Mabini (portal switch, deadlines on Today, eMabini grades, courses page) (#107)
- core + shell: eMabini client, sign-in, sync and stored data (#103)
- docs/ai.md: Android findings (#110)
- worktree.sh: new worktrees can build for iOS and Android straight away (#109)
- phone.sh: --release builds and opens the app (#108)

## 0.1.3 (2026-10-11)

- IntAssis UI: add LAR to the phone, ask him, confirm what he offers (#105)
- AI A5: on-device AI commands, and llama.cpp linked on iOS and Android (#104)
- docs: landing, login and portals specs (phase 1) (#95)
- core: Mabini theme is blue (#102)
- core: login guard against SIS lockouts (P0) (#100)

## 0.1.2 (2026-10-11)

- core: portal registry with Mabini as opens soon (#97)
- iOS release build links: keep line tables in the release profile (#99)
- Android: signed release builds for the beta (#72)
- AI A8/A9 (part): IntAssis turn, Why?, and outlines, logic only (#94)
- AI A7 (part): card batches and PDF text, no UI yet (#90)
- AI A4: model catalog, resumable download, SHA pin, RAM gate (#89)
- AI A3: chunks table and RAG over notes (#88)
- AI A2: intportal-llm (llama.cpp behind Llm, JSON-schema output, embeddings, eval) (#87)
- AI A0: llama-cpp-2 spike (macOS, iOS simulator, Android build) (#86)
- AI A1: intportal-ai crate (trait, prompt budgets, reply parsing, FakeLlm) (#85)
- docs: ADR 0003, on-device AI role (A0–A9) (#84)

## 0.1.1 (2026-10-10)



## 0.1.0 (2026-10-09)

- Docs: TEAM.md, roles and kickoff prompts for parallel sessions (#71)
- Builds: one Cargo build cache for every worktree, and scripts/worktree.sh (#70)
- CI: two jobs that always run, and an iOS simulator build on main (#59)
- Repo: stop tracking review screenshots, add issue and PR templates (#58)
- Docs: a curated architecture, and a CodeGraph index kept local (#57)
- Android: the iOS app on Android, with a Live Update for the Dynamic Island (#55)
- README for GitHub and a CLAUDE.md with the working loop (#54)
- Device calendar: classes in an IntPortal calendar, your events on Today (#53)
- IskoLAR across the app: LAR talks, Isko cheers (#51)
- IskoLAR landing: a pentomino portal builds itself, LAR comes through (#50)
- App basics: loading and error states, hold for class actions, Dynamic Type, better haptics (#49)
- Dynamic Island phones: no capsule in the app, a tighter Live Activity (#48)
- Encrypt each student's store with SQLCipher, key in the keychain (#52)
- One-line island on Dynamic Island iPhones (#47)
- Phone builds on a free Apple team (#46)
- Next class in the Dynamic Island, Lock Screen and a home-screen widget (#45)
- UI pass 5: where-you-stand strip on Today, swipe between days (#44)
- Security: per-student stores, Face ID lock, app-switcher cover (#43)
- UI pass 4: offline notice with retry on Today (#42)
- UI pass 3: haptics and pull to sync (#41)
- UI pass 2: Isko and a first run that asks for notifications at the right moment (#40)
- UI pass 1: week grid, System room, keyboard-safe chrome (#39)
- Keep the student's own work across sign-out (#38)
- Deadline and study reminders (#36)
- Coach: one factual nudge on Today (#35)
- P2.7 Study: FSRS flashcards, three modes, streak (#34)
- P2.6 Syllabus: grading calculator, outline import, due this week (#33)
- P2.5 Notes: freeform notes, search, Markdown export (#32)
- P2.8 Calendar: export classes as .ics through the share sheet (#31)
- P2.5 Notes, first slice: class notes and day notes (#30)
- P2.4 Grades: past terms, overall GPA, units, what do I need (#29)
- P2.3 Schedule: move classes, subject colours, hide vacant (#28)
- P2.1 Island: merge the glance into the Dynamic Island, dock it elsewhere (#27)
- Storage: one Cargo workspace, lean dev builds, disk and clean scripts (#17)
- Shell prototype: portal landing, island, Today with living campus, Schedule, Grades stamps, rooms (#16)
- Core crate: parsers, GPA, SIS client, today/glance, SQLite store (#14)
- S1: Tauri 2 + Svelte mobile shell spike, and CI (#13)

