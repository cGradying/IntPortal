# Changelog

What changed in each release, newest first. A release PR adds its section; `scripts/version.sh` sets the version.

## Unreleased

- Licence: IntPortal is all rights reserved from 2026-11-20. The official builds stay free to download and use; copies taken before then keep PolyForm Noncommercial.

## 0.5.0 (2026-11-17)

IntAssis, rebuilt: an install that finishes on any phone, a smarter and faster LAR that answers what it knows, and flashcards that work.

- Adding IntAssis keeps going when you lock the phone or leave the app: iOS downloads in the background, Android shows a progress notification. A full install screen shows each file, the percent, speed and time left, with Pause and Resume, and a cut-off download carries on by itself (#317)
- Before anything downloads, the app checks free storage and says exactly how much to free. The memory check now looks at the phone's RAM size instead of what other apps happen to use, and says "memory (RAM)" instead of sounding like storage (#317)
- A dropped connection is waited out and resumed instead of failing; each error says what to do (#317)
- LAR's brain is now Qwen3.5 2B: on Android it starts answering about three times sooner than before. Qwen3 1.7B stays as an option on the IntAssis card. Phones with the old Gemma model keep it until the update arrives (#318)
- LAR answers school and everyday questions from what it knows, not only from your notes. Your notes come first when they cover the question; otherwise the answer says "From what I know, not your notes. I might get facts wrong, so double-check anything important." (#319)
- Homework gets a tutor: LAR explains the steps and asks you one to try, but won't write a whole essay to hand in (#319)
- Talk to LAR like a person: greetings, a bad day or stress get a warm reply that asks about you, not a canned line (#319)
- LAR replies in English; Taglish and Filipino are still understood (#319)
- After an answer from what LAR knows: "Explain it simpler" and "Quiz me on it" (#319)
- Flashcards LAR makes are real cards: a term on the front, its meaning on the back. A card whose answer repeats the question, gives the term away or is a question itself is dropped. Cards on a topic use your notes first; cards with no notes behind them ask you to check them before you save (#320)
- A phone without the RAM for LAR's brain is told so before anything downloads, instead of after 1.5 GB; when the default model is too big but Qwen3 1.7B fits, that one is offered (#322)
- Android 15: the keyboard no longer covers the text box you're typing in (sign-in, LAR, every form) (#322)
- iPhone: both IntAssis files go to the background download at once, so the whole install can finish while you're away, not just the first file (#323)

Known gaps:

- Tried on the Android emulator and the iOS Simulator: the download keeps going with the app in the background and finishes on its own. Not yet tried on a real phone; the speed numbers are from a Mac
- A 2B model's own facts are sometimes wrong; that's why answers without your notes carry the disclaimer
- iPhone: no App Store or TestFlight build (needs a paid Apple developer account); sideload or build it
- Desktop builds are unsigned; IntAssis runs on the Mac only

## 0.4.0 (2026-11-17)

IntPortal on every platform: phones, computers and the browser, with a website and a reel.

- Class card outside the app: You › Reminders has a new "Class card outside the app" setting: Always, When I leave (the default), or Off. In the default the Lock Screen and Dynamic Island card (the status-bar chip on Android) goes away when you open IntPortal and comes back when you leave it
- The status dock above the tab bar no longer sits over your lists when there is nothing to count down to
- README and architecture doc rewritten for 0.3.0, with new screenshots
- On every computer: IntPortal for Mac (Apple Silicon), Windows and Linux, the same app in a phone-sized window, with the login in the system's keychain and the data encrypted on that computer (#306)
- In any browser: Look around runs on the website at /try, the real app on demo data, with the Rust core compiled to WebAssembly. Nothing is sent or kept (#305)
- The website: downloads for every device, install help, privacy and questions, ready to put on any static host (#304)
- The reel: 46 seconds of the real app, in 9:16 and 16:9 (#308)
- iPhone: an unsigned build for AltStore or SideStore comes with each release (#303)
- Sign-in can't be fooled into a lockout: the guard takes its limits from the portal, a broken count file means no tries for 15 minutes instead of a fresh count, and each try is saved before any password is sent (#303)
- Studying plays like a card game: streaks multiply points, quick answers earn a bonus, a missed card comes back once, and each deck keeps a best score; it follows You › Done effects and Reduce Motion (#313)
- Decks say how much you know ("62% known") and what's due over the next seven days (#303)
- A syllabus marks the rows dated this week (#303)
- Links from eMabini open only on PUP's own sites (#303)
- The quick add's subject guess (COMP picks the class that meets that day) moved into the core, and a fix stays with its own line when you edit a pasted list (#303)

Known gaps:

- iPhone: no App Store or TestFlight build (needs a paid Apple developer account); sideload or build it
- Desktop builds are unsigned; Windows and Linux builds are made by CI and haven't been run on a real Windows or Linux computer yet. IntAssis runs on the Mac only
- The website is ready but not online; putting it on a host and a domain is the owner's step (site/README.md)

## 0.3.0 (2026-11-17)

The first public release on Android.

- Meet LAR: before the portal, a new student talks with LAR on a page of his own. He asks what to call you, your campus and what you need most, shows how the app works inside the conversation (a class countdown you scrub, a deadline you tick, a study card you flip, a "No signal" switch), lets you pick a look and reminders, then flies back into the portal, which opens for sign-in (#295)
- Motion: one shared set of animation helpers and timings for the whole app. Tabs slide in the direction you move and keep their scroll; sheets rise with a slight settle and close when you drag their grab bar down; the tab block glides; a pressed button can no longer stay stuck on iOS; pull to sync resists (#294)
- Each screen's one moment: Today's countdown steps to its new value, the progress bar glides and a class that starts gets one gold sweep; Schedule's day slides in from the side you tapped; Grades draws its trend once per new term data; study cards flip in 3D and the next one slides in; lists move instead of jumping (#293)
- Scan: a scanned photo's text is tidied on the phone at once (line wraps joined, split words rejoined, page numbers dropped, codes and dates kept exact). With IntAssis on, LAR then fixes the OCR mistakes, "Tidied by LAR · Show original", and his version is refused if it changes any number, code or date (#297)
- Public: a privacy policy (PRIVACY.md), an Android install guide in the README, and You shows the version, that the app is unofficial, and links to Privacy, Updates and Report a problem (#296)

Known gaps:

- iPhone: no App Store or TestFlight build (needs a paid Apple developer account); build it yourself with the README steps
- Android without Google Play services can't download the scanner; typing and pasting still work
- Not yet felt on many phones: motion at 60 fps on low-end Android (#231), all-day deadlines in Android's calendar (#205)

## 0.2.1 (2026-11-16)

From the owner's phone QA of 0.2.0.

- Intro: a new student pages through nine pages before the form, one feature each, every page something to touch. LAR asks what to call you and answers by name; pick your campus; drag a clock and watch Up next turn into In session; tick a deadline; flip a study card; flip "No signal" and see your data stay; wear a look; allow reminders with a sample notification; then sign in or look around (#289)
- Landing: only the night and the stars behind the portal; the dot grid, the lit ground and the reflection are gone (#289)
- In session: a pixel scene of your own campus, drawn by a shader, for all 25 PUP campuses and other schools in the portal wall. Sta. Mesa has the Pylon, the Mabini Obelisk, the Main Building and the lagoon; the sky follows the hour and the window of your next class is lit. Change it in You › Campus (#290)
- Today: only In session and Due at the top; LAR's nudge and This term moved below your classes, and the note for today sits in the day list's head (#288)
- Due: Done is the box, a struck title and the DONE stamp, then the row folds away with Undo; the sparks, ripple, combo and bursts are gone. Add is a gold "+ Add" that no longer stays squashed after the sheet opens over it. LAR no longer pops up when you tick a deadline or clear them all (#288)
- Haptics work: the app now asks the phone for each kind of vibration it uses; before, every one was refused in silence. A CI check catches a capability that grants nothing (#287)
- Pinch and double-tap zoom are off, and a text field no longer zooms the page when focused (#287)
- Smaller: Android APK 69.7 MB to 22.3 MB and Play bundle 37.3 MB to 13.2 MB; iPhone release 18 MB installed (7.7 MB download). Link-time optimisation now actually runs, Android ships arm64 only, and Android's scanner downloads its models on first use. `scripts/phone.sh` builds release by default (#291)

Known gaps:

- Not yet felt on a phone: the haptics fix, the shader scene's battery cost, the intro's page motion at 60 fps
- Android without Google Play services can't download the scanner; typing and pasting still work
- No store builds yet (#26)

## 0.2.0 (2026-11-15)

- Welcome: a new student sees what the app is before any form. Under the portal, three tabs to touch: Inside opens the peek on Today, Schedule, Grades or Study; What it does has LAR explain reminders, deadlines, offline use, privacy and his nudges; Make it yours re-tints the landing in six dark looks and keeps the pick for the app (#282, #283)
- Landing: one world with the app. The night ground and its dot grid, a portal lit from inside that stands on its own reflection, still stars, and only the portal moving at rest. Peek, an "SIS is up" check that sends no login, Look around (in release builds too), how your login is kept, and Forgot password, all before signing in (#281, #282)
- Choosing a school: a plaque with the school's mini portal opens the portal wall, with Open now (SIS, eMabini) first, then recent, your region and A to Z (#281)
- Today: Done is one 44 pt chip beside each deadline, and the title gets the row's width (#284)
- Schedule: the gold tile under the chosen day shows again; "Due, next 4 weeks" says what the little map is (#284)
- Grades: the GPA trend has guides at 1.00, 1.50 and 2.00, its first and last values and a spoken summary; an "All passed" pill when every subject passed (#284)
- Study: each rating shows when the card comes back (10m, 1d, 3d…), and the end of a round shows your score and each card's next review (#284)
- LAR no longer says "Nothing due" while the Due card lists something; source chips in his chat survive a restart; the tab bar stays put when a field is focused from code; nothing animates behind his window or while the app is hidden (#279)
- Faster: a screen reads the student once instead of twelve rows, one tick writes one row instead of twelve, and no command runs on the main thread (load 374 µs to 24 µs, one edit 501 µs to 142 µs, in memory) (#278)
- One art style: every type size, duration and corner from a token, 44 pt tap targets everywhere, and the same dotted ground under every screen (#280)
- The 3D crystal is back as LAR's chat chip; the chat still opens with the pixel dither (#274)
- Release: a privacy manifest for iOS, a content security policy, and an Android release build in CI

Known gaps:

- Not yet run on a real phone: the camera scan, note photos, keep-screen-awake, the backup share sheet, and the frame rate of the landing and the dither opening
- A low-end Android check of the crystal and the dither (#231), and all-day deadlines in Android's calendar (#205)
- No store builds yet: TestFlight and Play testing need store accounts (#26)

## 0.1.10 (2026-11-14)

- LAR's chat button is a flat pixel chip: a 3x3 grid in the room's tones with a gold dot on each part that holds data. On Study and in the note editor its corners dither away into a gold +, and an open menu shows a pixel X. While LAR thinks, a pixel dither runs across it (#271)
- The chat opens as a pixel dither that grows out of the chip in 0.42 s, and closes back into it; the 3D crystal and its pour are gone (#272)
- Android: the release build merges the camera's file sharing with the app's (#264)

Known gaps:

- Not yet run on a real phone: the camera scan, note photos, keep-screen-awake and the backup share sheet
- The dither opening has not been timed on a low-end Android phone

## 0.1.9 (2026-11-14)

- Landing: tap the portal to peek at what the app keeps (Today, Schedule, Grades, Study, sample data); a ring runs through its tiles; carry LAR around; a one-line pitch; the portal lifts as the form rises (#252)
- Launch: the signed-in dive takes 1.8 s instead of 0.6 s, then the day says hello and Today rises; Short and Off are in You (#235, #252)
- Sign-in: birthdate wheels, a masked student number, Sign in only when the form is valid, plain rejected and SIS-down states with Try again; a sign-in with no schedule yet still lets you in (#256)
- Deadlines: one Due card for SIS, eMabini and your own; Done with a 5-second Undo and a "Done this week" row; long-press offers Done; type or scan a deadline from a photo (#202, #208, #238, #254, #259)
- Deadlines in the phone calendar and as .ics; reminders open the subject's outline (#204, #262)
- LAR plans the day: free stretches, warm-ups, after-class notes, grade risk, a Sunday brief, at most 3 nudges a day (#206, #259)
- Schedule: the pixel week, a readable Day view, tap to open a day, a week range header and a springy swipe (#217, #259)
- Study: part tiles (Review, Notes, Cards, Done), notebooks per subject, review all due across decks (#232, #237, #210)
- Notes: a formatted Markdown editor with 15 tools, page look (size, font, spacing, paper), templates, dated entries, checklists that tick without the keyboard, Make cards; photos in notes, shared as a zip with the note (#255, #258)
- Class links: add a meeting link and your own description to a class; Join shows on Up next 15 minutes before an online class (#261)
- LAR's chat: the crystal pours into a window with the sky header and a trace of LAR's real steps; suggestions follow the day (#246, #250, #251)
- You: quick switches and search, grouped settings, a theme maker with share codes and QR, backup and restore (no password, never your logins), space used (#243, #247, #257)
- Look: one night, your school's accent across the app, a living ground, pixel numerals, the done run, 44 pt tap targets, motion tokens (#213–#218, #260)
- Plain words for errors everywhere; honest loading and "Showing what was saved" (#209, #262)
- The Isko mascot is retired; LAR is the only character (#233)
- IntAssis on phones with 6.5 GB of RAM or less keeps one model loaded at a time, says "Still waking up. This phone is slow." after 15 s and stops after 150 s with a low-memory note (#190)
- Mabini: sign-in and sync fixes (#193)
- LAR's hands glide into gestures; no cream flash on launch (#170, #171)

Known gaps:

- Not yet run on a real phone: the camera scan, note photos, keep-screen-awake and the backup share sheet
- The pour opening at 60 fps on a real iPhone and a low-end Android check are still open release gates
- Spec 045's text roles and motion tokens are partly applied (#260 lists the files left)

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

