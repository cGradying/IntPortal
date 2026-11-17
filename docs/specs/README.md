# Specs

No UI work starts without an approved spec. A spec says what the student sees and does, in numbered criteria, before anyone builds it. Issues cite the criteria; tests are named after them; the Head reviews criterion by criterion.

## The flow

1. **Spec.** Copy `TEMPLATE.md` to `NNN-name.md` and fill it in. Status `draft`.
2. **Approval.** The user reads it and approves it in the spec PR. Status `approved`. Nothing is built before this.
3. **Issues.** Each issue cites the criterion ids it delivers (`010-landing C4`, `C7`).
4. **Tests.** Tests carry the criterion id in their name (`c4_frame_builds_from_bottom_centre`). The spec's test map lists which test covers which criterion, or "screenshot" when only the simulator can show it.
5. **Review.** The Head checks the PR against each cited criterion and says which hold. Status `building` while PRs land, `shipped` when every criterion is delivered.

A change that contradicts an approved spec changes the spec first, in the same PR, and the user approves the change.

## Numbering

- `000-099` shared reference (data maps, glossaries).
- `010-019` first-run and sign-in (landing, login, portals).
- `020-029` IntAssis (on-device AI).
- `030-039` Features from the macOS app, wave by wave.
- `040-049` everyday UX: deadlines, trust and speed, the day plan.
- `050-059` the release: finishing the app, the website, the browser demo, desktop, the reel.
- Later ranges follow the app's areas as they get specs.

Criterion ids are `C1`, `C2`, … within one spec and are never reused or renumbered once approved; a dropped criterion is marked *removed*.

## Index

| Spec | Status | Covers |
|---|---|---|
| [000-sis-data-map](000-sis-data-map.md) | reference | What the app reads from the SIS, and where it lands |
| [010-landing](010-landing.md) | shipped | The tile portal, its states, the carousel, the dive, touch and the peek |
| [011-login](011-login.md) | shipped | The sign-in form, errors and the lockout guard |
| [012-portals](012-portals.md) | shipped | The portal model: SIS now, Mabini next |
| [013-mabini](013-mabini.md) | shipped | eMabini: sign-in, courses, deadlines and grades, the guard, eMabini alone |
| [020-ai](020-ai.md) | shipped | LAR that streams, remembers, cites notes; Ask AI in a note |
| [021-intassis-v2](021-intassis-v2.md) | approved | Background install with an install screen, Qwen3.5 2B, a tutor that answers from what it knows, checked study cards, a faster first word |
| [030-from-the-mac-app](030-from-the-mac-app.md) | shipped (wave 1) | The Mac app's features mapped to the phone; wave 1: join links, deadlines in the calendar, dated note entries |
| [040-trust-and-speed](040-trust-and-speed.md) | shipped | Honest loading and errors, fixable logins, review all due, consistent taps, week navigation |
| [041-one-deadline-list](041-one-deadline-list.md) | shipped | Syllabus, eMabini and own deadlines in one list: Today, reminders, LAR, calendar; add by typing or photo |
| [042-lar-plans-the-day](042-lar-plans-the-day.md) | shipped | Gap plan on Today, warm-up and after-class nudges, grade risk, Sunday brief, 3-a-day budget |
| [044-pixel-week](044-pixel-week.md) | shipped | Week and Day, tap to open a day, details first, stamps, now-line |
| [045-app-environment](045-app-environment.md) | shipped | One night, gradient ground, Pixel-bridged type, the done run, moving around |
| [046-study-and-notes](046-study-and-notes.md) | shipped | Notes sorted by subject, formatting, templates, photos, note to cards, a Done you can find |
| [047-you-and-themes](047-you-and-themes.md) | shipped | You on one screen, search, new settings, backup, custom themes shared by code and QR |
| [048-lar-chat](048-lar-chat.md) | shipped | LAR's chat, round four: the cube pours into it, the sky header, his real steps as a pixel trace, suggestions that follow the day |
| [049-intro](049-intro.md) | shipped | A talk with LAR before sign-in: your name, campus and what matters, live cards, a look and reminders |
| [050-release-0.4](050-release-0.4.md) | shipped | Finish the app for 0.4: guard hardening, deck mastery and forecast, this week in a syllabus, eMabini fixes, stable release files |
| [051-website](051-website.md) | shipped | The download website: the right file for each device, install help, privacy, questions |
| [052-try-in-browser](052-try-in-browser.md) | shipped | Look around in any browser, on the Rust core compiled to WebAssembly |
| [053-desktop](053-desktop.md) | shipped | Mac, Windows and Linux builds of the same app |
| [054-reel](054-reel.md) | shipped | A new launch reel made from the app, and its page on the site |
| [055-study-game](055-study-game.md) | shipped | The study session plays like a card game: combo, soft clock, LAR, results |
| [056-web-app](056-web-app.md) | draft | Future: the same app in any browser, signed in, with data kept in the browser |
| [057-website-v2](057-website-v2.md) | approved | The website, second edition: a 3D portal hero with the dive, a feature directory, help, changelog, roadmap and About |

Decisions behind them: [ADR 0004](../adr/0004-landing-renders-in-rust-wasm-tiles.md), [ADR 0005](../adr/0005-portals-are-first-class.md) and [ADR 0006](../adr/0006-one-repo.md).

The release plan for 0.4, the website and the reel is [PLAN-release-0.4.md](PLAN-release-0.4.md).

## Reference material

`reference/` holds the visual prototype and the capture guide. Raw SIS and Mabini captures and third-party art stay local in `reference/private/`, which git ignores. See [reference/README.md](reference/README.md).

The working plan that produced these specs is [PLAN-landing-login.md](PLAN-landing-login.md).
