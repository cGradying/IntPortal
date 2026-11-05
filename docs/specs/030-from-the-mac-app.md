# 030 From the Mac app

**Status:** draft

## What changes for the student

Features students used in the macOS IntPortal come to the phone, in waves. Wave 1: a join link on each online class, and a dated entry in a class note with one tap. Deadlines in the phone's calendar moved to spec 041.

## Direction and references

- The macOS app, [cGradying/IntPortal](https://github.com/cGradying/IntPortal) (`origin/main` 00df2b5), is in maintenance. Its features are in `docs/legacy/FEATURES.md` and in the parity table below.
- A feature moves when it helps a student on a phone. A Mac-only habit (printing, the menu bar, auto-update) stays behind.
- Logic goes in the Rust core with a test; the phone keeps doing what the core returns ([ARCHITECTURE.md](../ARCHITECTURE.md)).
- This spec covers the parity map and wave 1. Each later wave gets its own spec (031, 032, …) before it is built.

## Parity

The Mac app's features and where each stands on the phone, from the Head's inventory of 2026-10-15. **Done**: on the phone already. **Partial**: the gap is named. **Wave n**: planned. **Won't port**: with the reason.

| # | Mac feature | Phone |
|---|---|---|
| 1 | SIS sign-in and scrape, failover between SIS hosts | Done (`sis/`) |
| 2 | Opens offline from a cache, survives a corrupt cache | Done (`store.rs`) |
| 3 | Week grid, week navigation | Done (`WeekGrid.svelte`, Day and Week) |
| 4 | Now-line | Done |
| 5 | Year view | Deferred |
| 6 | Print the week | Won't port: phones don't print timetables; share the `.ics` instead |
| 7 | Next-class banner | Done (Up next) |
| 8 | Today agenda, free gaps, tomorrow | Done (`today.rs`) |
| 9 | Menu bar panel | Done as the Live Activity, Live Update and widget |
| 10 | Online or vacant per week or term, hide cancelled | Done (Hide vacant classes) |
| 11 | Moved class time, subject colours | Done |
| 12 | Class description and online-meeting link | **Wave 1** (C1–C5) |
| 13 | Other calendars drawn on the grid | Partial: read as busy time, not drawn |
| 14 | Create, move and resize events on the grid | Won't port: the phone's calendar app does this |
| 15 | Classes in the device calendar | Done (IntPortal calendar) |
| 16 | `.ics` export | Done |
| 17 | Google sign-in, Google Calendar export | Won't port: the device calendar and `.ics` cover it, with no Google login |
| 18 | Class reminders | Done |
| 19 | Start at login, Sparkle, update check | Won't port: app stores and the OS do this |
| 20 | Portal landing and sign-in | Done (spec 010, 011) |
| 21 | App shell with six places | Done as five tabs |
| 22 | Grades, units-weighted GPA | Done |
| 23 | Past terms, GPA trend, units done | Done |
| 24 | Grading calculator | Done (Subject, Grading) |
| 25 | Class note across weeks, day note | Done |
| 26 | Notes vault with folders and tabs | Moved to [046](046-study-and-notes.md): sorted by subject |
| 27 | PUPNotes live Markdown editor | Moved to [046](046-study-and-notes.md) C9 (#20) |
| 28 | Checkboxes, KaTeX, code, `[[links]]`, tables | Moved to [046](046-study-and-notes.md): checkboxes and code; the rest later |
| 29 | Images in notes | Moved to [046](046-study-and-notes.md) C15–C17d |
| 30 | Dated log entry in a class note | Moved to [046](046-study-and-notes.md) C14, C14a |
| 31 | Colour labels on notes | Deferred; [046](046-study-and-notes.md) sorts by subject colour |
| 32 | Export a note as .md, .txt, PDF | Partial: .md; [046](046-study-and-notes.md) C17 adds photos as a zip |
| 33 | Choose which notes the AI reads | Wave 4; touches `rag.rs`, needs the Code engineer first |
| 34 | Decks, FSRS, manual cards | Done |
| 35 | Study modes: flash, identification, choice, true/false, matching | Partial: flash, type, choice. Wave 4: true/false and matching |
| 36 | Study streak and stats | Done |
| 37 | AI cards from notes, reviewed before saving | Done |
| 38 | Cards from a PDF, DOCX, PPTX, MD or TXT file | Wave 2 |
| 39 | Generation that keeps running when the sheet closes | Wave 2 |
| 40 | Explanation after a wrong answer | Done (Why?) |
| 41 | Syllabus from a file or pasted text | Partial: paste only. Wave 2: from a file |
| 42 | AI syllabus extraction with grading weights | Wave 2 (#82) |
| 43 | Study guide from the subject alone | Wave 2 (#93) |
| 44 | Syllabus table and timeline | Partial: one list |
| 45 | Syllabus deadlines into the calendar | Spec 041 (C21–C24) |
| 46 | Quiz from a syllabus topic | Wave 4 |
| 47 | Assistant chat grounded in the student's data | Done (IntAssis) |
| 48 | Assistant actions: calendar event, syllabus item | Partial: note, reminder and cards. Wave 4: the rest |
| 49 | Slash commands | Won't port: starter chips and intents do this on a phone |
| 50 | RAG over notes with sources | Done |
| 51 | AI on a selection in a note | Partial: no custom prompt |
| 52 | Local model, catalog, download, memory check | Done (`intportal-llm`) |
| 53 | Cloud AI providers | Won't port: local only ([ADR 0003](../adr/0003-on-device-ai-llama-cpp.md)) |
| 54 | AI tuning knobs | Won't port: one tuned setting per phone class |
| 55 | Themes and fonts | Themes done (rooms). Fonts deferred |
| 56 | Storage pane | Partial: the model only (#91) |
| 57 | Reset per pane, force Reduce Motion | Partial: "Erase everything"; the system setting rules |

## Keep

- The class sheet's meeting choice (In person, Online, Vacant), Change its time, Colour, and Syllabus & grading.
- The IntPortal calendar: classes only in it, rewritten on change, the student's own calendars untouched.
- Class notes keyed `class:<code>`, shared across weeks.

## Behaviour

**Class link and description (Mac #12)**

- **C1.** A class can hold a meeting link and a description the student writes, kept per subject code. They survive every sync and sign-in, and "Erase everything" removes them.
- **C2.** The link must be an `https://` address. Anything else is refused with the copy below, and nothing is saved.
- **C3.** The class sheet shows the student's description above the SIS one, and a **Join class** button when a link is set. Join opens the link in the phone's browser.
- **C4.** Up next on Today shows **Join** when the next class is marked online for that meeting, has a link, and starts within 15 minutes or is in session.
- **C5.** Clearing the link or the description removes it; the sheet goes back to the SIS description alone.

**Deadlines in the calendar (Mac #45)**

- **C6–C10.** *Removed* (2026-11-03). They moved to [041](041-one-deadline-list.md) C21–C24, which cover syllabus, eMabini and own deadlines.

**Dated entry in a class note (Mac #30)**

- **C11–C14.** *Removed* (2026-11-05). They moved to [046](046-study-and-notes.md) C14 and C14a. The date logic stays in the core with a test, as C12 said.

## Copy

- Class sheet: **Join class**, **Meeting link**, **Your description**, placeholder "https://meet.google.com/…", **Clear link**.
- Today, Up next: **Join**.
- Error (C2): "Use a link that starts with https://".
- Note editor: **Add entry**.

## Data shape

- `crates/intportal-core/src/store.rs` `Snapshot` gains `class_info: BTreeMap<String, ClassInfo>` (subject code to info), `#[serde(default)]`, so existing stores load.
- `ClassInfo { link: Option<String>, about: Option<String> }`, in `today.rs` beside `Marks`, or its own small module.
- A `set_class_info(subject_code, info)` command following `set_color` in `src-tauri/src/lib.rs`, returning the `Snapshot`. This is a hot file: it waits for #60 or goes in a small PR (TEAM.md, Working in parallel).
- `notes.rs` or `today.rs`: `entry_date(sessions, marks, code, today) -> Date` for C12; the editor inserts the heading.

## Errors

- A non-https link: the C2 copy under the field; nothing saved.
- Calendar permission denied: no deadline events, the same as classes today; You keeps showing the calendar switch as it does.
- A class with no future meeting (the term ended): Add entry uses today's date.

## Motion and Reduce Motion

No new motion. Join and Add entry use the existing button press and haptic.

## Accessibility

- Join is a button labelled "Join <code> class" with a 44 pt touch target.
- The link and description fields have visible labels and work with Dynamic Type.
- Add entry is reachable by VoiceOver in the note's toolbar.

## Out of scope

- Waves 2 to 4 (specs 031+), the year view, fonts, note colour labels.
- Opening meeting apps directly (Zoom, Meet); the browser hands off to them.

## Test map

| Criterion | Check |
|---|---|
| C1 | `cargo test -p intportal-core c1_class_info_survives_sync` |
| C2 | `cargo test -p intportal` or core `c2_link_must_be_https` |
| C3, C5 | vitest on the sheet's view model; screenshot on the iPhone 18 Pro |
| C4 | `cargo test c4_join_shows_within_15_minutes` (if computed in the core) or vitest; screenshot |
| C11, C14 | vitest on the insert function |
| C12, C13 | `cargo test c12_entry_date_skips_vacant_weeks`; vitest for the locale format |

## Open questions

- Should Join also appear for a class marked in person that has a link (a hybrid class)? The recommendation is yes, on the sheet only, not on Today.
