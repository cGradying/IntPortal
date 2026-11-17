# intportal-web, kept for reference

`intportal-web` was a hosted, multi-user web port of the old macOS app. It was built in September 2026 and is now the private, archived repo `cGradying/intportal-web-archived`. Its last commit is `6efca1f` (2026-09-05). This folder keeps only what a future IntPortal web app can use. Everything else stays in the archive.

## What it was

- React 19, Vite and TypeScript in the browser.
- One FastAPI app on Vercel's Python runtime, with Neon Postgres.
- The server signed in to SIS for each student and scraped the schedule and grades. It stored the SIS password and session cookies encrypted, with a key derived from the student's own password (Argon2id, then AES-GCM).
- AI called Anthropic with a key the student supplied, through a server proxy.

## Why it isn't merged

IntPortal's promise is that there is no server and everything stays on the device. intportal-web broke that by design: its own `PRODUCT.md` lists both breaks. It was also a second app in a second stack, rebuilding scraping the Rust core already does. See ADR 0006.

## What is kept here

- [THREAT-MODEL.md](THREAT-MODEL.md) covers the threats and controls for a service that holds other students' logins. Read it before anything in IntPortal runs on a server, such as IntPortal Cloud or a sign-in relay.
- [TERMS.md](TERMS.md) is draft terms of use for a hosted, unofficial student service.
- [PRODUCT.md](PRODUCT.md) lists the commitments a hosted version cannot keep, and how to say so plainly.

## Lessons from its SIS code

These were learned against the live SIS, in its last commits:

- The SIS host is `sis8.pup.edu.ph`, not `sis1`.
- The login POST must carry the submit button's `name=value` pair, or SIS ignores it.
- Scrape the schedule and grades right after sign-in, not only on a manual refresh.
- Its last fixes were made against SIS from Vercel, so signing in from a cloud host seems to work. Check that again before a relay depends on it.

## Features it had that IntPortal doesn't yet

- Google Calendar sync. IntPortal exports `.ics` only (`crates/intportal-core/src/calendar.rs`).
- A year view of the schedule.
- Reading syllabi from Word and PowerPoint files (`api/opc_extract.py`, which unzips the Office XML).

Everything else it had, IntPortal now has natively: the week schedule, grades and GWA, notes, FSRS flashcards and quizzes, your own deadlines, syllabus import and the assistant.

## Getting the code

Run `gh repo unarchive cGradying/intportal-web-archived` to work in it. A full git mirror is also at `~/Workspaces/Personal Work/intportal-leftovers/mirrors/intportal-web.git` on the owner's Mac.
