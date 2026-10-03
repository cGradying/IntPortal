# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

One custom design language on iPhone and Android, served in a Tauri webview. It still follows each phone's gestures, safe areas, haptics and text size.

## Users

PUP (Polytechnic University of the Philippines) students. They open the app several times a day on their phone, mostly in short glances: what class is next and where, did a grade post, what's due this week. They study on the same phone between classes.

## Product Purpose

IntPortal is an unofficial, offline-first companion to PUP SIS. It signs in to SIS for the student, keeps their schedule and grades on the phone, and adds what SIS lacks:
- a day and week view with marks (vacant, online, moved);
- reminders;
- class and day notes;
- syllabus pages;
- spaced-repetition study decks;
- a coach that gives one factual nudge at a time.

Success means students open it instead of SIS, every day.

## Positioning

It works offline after one sign-in. Everything stays on the phone, and the app only ever talks to PUP SIS. IntPortal Cloud is planned as an opt-in paid tier: sync, plus a browser view on any laptop.

## Operating Context

- Phones on campus, often on weak data.
- Students check between classes, while walking, in jeepneys.
- The SIS itself is slow and often down.
- Taglish is the everyday register.

## Capabilities and Constraints

- The schedule, grades, past terms and GPA come from SIS. Marks, moves, colours, notes, decks and syllabus pages are the student's own.
- Rust core, Svelte 5 UI.
- Sign-in uses student number, birthdate and password.
- A demo mode exists in review builds.
- The free Apple developer account means no App Groups (no home-screen widget data yet). The Live Activity works without them.

## Brand Commitments

- **Name:** IntPortal, written "Student IntPortal" on the landing.
- **Mascots: IskoLAR.**
  - **Isko** is the 14×20 pixel student; he stands for the user. The user will redesign him later, so don't redesign him unasked.
  - **LAR** (Lakbay-Aral Robot) is a small obsidian robot from the portal's other side. He is the voice: coach, tips, empty states, and later IntAssis.
  - ISKO + LAR = ISKOLAR, as in *Iskolar ng Bayan*.
- **The portal** is the brand's core image. Swirl ramp: #170509, #540a1c, #941c30, #cca128, #faebb3.
- **Voice:** friendly, light Taglish, clear first.

## Evidence on Hand

- Real app screens: in the repo.
- The film rig and LAR's source art: `~/Workspaces/Personal Work/intportal-films` (read-only).
- No user counts, ratings, testimonials or press. Never invent them.

## Product Principles

1. Clear first, charming second: the pixel world never slows a glance.
2. The student's data stays on the phone; say so plainly where login happens.
3. Never imply it's official: no PUP seal or wordmark. Maroon and gold and the plain name "PUP SIS" are fine.
4. Every action is two taps or fewer.
5. Delight is earned by craft: no generic effects, nothing that only decorates.

## Accessibility & Inclusion

- Follows the iOS text size: headings capped at 1.3×, body at 1.8×.
- Reduce Motion skips animations to their resting state.
- Haptics can be turned off.
