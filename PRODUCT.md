# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Currently shipped: native macOS 26+ (SwiftUI + WKWebView, `Sources/PUPSISPortalApp/`) and a native Windows port (WinUI/C#, `windows/`) with a mirrored core (`DayAgenda`, `NotesStore`, `Preferences`, etc. exist on both sides). iOS is a planned future surface — the design language needs to travel there, not just to Windows. This project has no `web`/`ios`/`android` single-platform identity; treat macOS as primary today, with Windows as an actively-maintained sibling and iOS as future.

## Users

PUP (Polytechnic University of the Philippines) students who have their own SIS8 (Student Information System) account. They're checking their own schedule and grades, and increasingly using the app to actually study (notes + AI-generated quiz decks) — not just as a faster way to see class times.

## Product Purpose

A native portal that signs into the student's own PUP SIS8 account headlessly and renders their schedule, grades, and study material as real native UI — instead of navigating the official (slow, dated) SIS web portal directly. The stated vision: "a portal for students for easier access" — lower friction to the same data they already have access to, plus tools (notes, AI-generated quizzes) the official portal never offered at all.

## Positioning

Two mechanisms neither the official SIS8 site nor the sibling project (`PUPSIS`, which only auto-fills the real site's forms) offer, roughly equal weight:

1. **The SIS web UI is never shown.** The web view exists only to hold an authenticated session and run scraping JS in the background; everything the student sees is native SwiftUI/WinUI, not a wrapped browser tab.
2. **Local-only AI study tools tied to the student's real schedule.** Notes vault with RAG-backed AI drafting/summarizing, and AI-generated flashcard/identification/multiple-choice/true-false/matching quiz decks with FSRS spaced-repetition scheduling — all running on a local Ollama model, nothing leaves the machine.

## Operating Context

Students sign in once with their real SIS8 credentials (Keychain-stored, never logged/printed). Primary workflows: checking today's schedule and free time between classes, exporting classes to the system calendar, reviewing grades each term, taking notes per class/day/event, and generating + studying AI quiz decks from those notes. Ollama running locally is required for AI features (notes drafting, quiz generation, explanations); everything else — including studying an already-generated deck — works with Ollama stopped.

## Capabilities and Constraints

- Scope is deliberately the user's own account and own data only — no scraping other students, no bypassing auth, no redistributing SIS content. This matches what PUP's Terms of Use actually permits, not a chosen restriction to loosen later.
- AI is local-only (Ollama on `localhost`), by design — not a missing feature, a stated privacy commitment (see `Sources/PUPSISPortalApp/Core/OllamaClient.swift`'s own doc comment: "a configurable host would quietly turn that from a fact into something the user has to verify").
- Credentials live only in the Keychain (service `ph.edu.pup.sis8.portal`, distinct from sibling project PUPSIS's `ph.edu.pup.sis8` so both can coexist on one machine).
- The Windows port mirrors macOS core logic but is a separate, actively maintained C#/WinUI codebase, not a wrapper — design decisions need a WinUI-native equivalent, not just a macOS-only fix.
- iOS is planned but not started; no iOS-specific constraints are confirmed yet.

## Brand Commitments

Name is fixed: **PUPSISPortal**. No app icon, logo, or other brand asset exists in the repo yet (confirmed absent — searched for `.icns`/`AppIcon`/logo files, none found). No confirmed voice/tone commitments beyond what the shipped UI already establishes; treat the existing terse, technically-precise doc-comment style and the "astra moon" navy/emerald default theme (`Core/Theme.swift`) as incumbent evidence, not a locked brand rule, until `/impeccable document` records it formally.

## Evidence on Hand

No testimonials, case studies, press, or external marketing copy exist — this has never been marketed; it's a personal/internal tool the author (a PUP student) built and uses. Future design work must not fabricate quotes, user counts, or "students love it" style claims. Real scraped SIS test fixtures exist in `Tests/PUPSISPortalTests/` but are treated as sensitive (personal data is never committed) — not usable as public-facing evidence/screenshots without sanitizing first.

## Product Principles

1. **Own data only, nothing leaves the machine.** Every design and feature decision defers to the ToU-scoped, local-only constraint — this isn't negotiable for growth.
2. **Native over wrapped.** The SIS web UI is never surfaced; if a feature would require showing raw SIS pages, it likely needs a different mechanism, not an embedded browser view.
3. **Easier access is the whole point.** Every surface should measurably lower the friction of getting to the data/tool the student already has a right to, not add ceremony on top of the official portal's own friction.
4. **Study tools are core, not bonus.** Notes and AI quiz decks are as central to the product vision as the schedule view — treat Notebook with the same design weight as the calendar, not as an appendix.
5. **One design language, several native shells.** macOS, Windows, and (planned) iOS are separate codebases sharing one product and, going forward, one visual world — a design decision made for one needs a real native equivalent for the others, not a description of "how it would look."

## Accessibility & Inclusion

No product-specific accessibility requirement has been confirmed beyond what's already implemented (Reduce Motion support exists across animated views — `Views/Quiz/QuizVisuals.swift`, `Views/AgendaView.swift`, `Views/NavIsland.swift`). Treat this as a baseline to preserve, not a ceiling.
