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
- Later ranges follow the app's areas as they get specs.

Criterion ids are `C1`, `C2`, … within one spec and are never reused or renumbered once approved; a dropped criterion is marked *removed*.

## Index

| Spec | Status | Covers |
|---|---|---|
| [000-sis-data-map](000-sis-data-map.md) | draft | What the app reads from the SIS, and where it lands |
| [010-landing](010-landing.md) | shipped | The tile portal, its states, the carousel, the dive, touch and the peek |
| [011-login](011-login.md) | draft | The sign-in form, errors and the lockout guard |
| [012-portals](012-portals.md) | draft | The portal model: SIS now, Mabini next |
| [020-ai](020-ai.md) | building | LAR that streams, remembers, cites notes; Ask AI in a note |
| [030-from-the-mac-app](030-from-the-mac-app.md) | approved | The Mac app's features mapped to the phone; wave 1: join links, deadlines in the calendar, dated note entries |
| [040-trust-and-speed](040-trust-and-speed.md) | approved | Honest loading and errors, fixable logins, review all due, consistent taps, week navigation |
| [041-one-deadline-list](041-one-deadline-list.md) | approved | Syllabus, eMabini and own deadlines in one list: Today, reminders, LAR, calendar; add by typing or photo |
| [042-lar-plans-the-day](042-lar-plans-the-day.md) | approved | Gap plan on Today, warm-up and after-class nudges, grade risk, Sunday brief, 3-a-day budget |
| [044-pixel-week](044-pixel-week.md) | approved | Week and Day, tap to open a day, details first, stamps, now-line |
| [045-app-environment](045-app-environment.md) | approved | One night, gradient ground, Pixel-bridged type, the done run, moving around |
| [046-study-and-notes](046-study-and-notes.md) | shipped | Notes sorted by subject, formatting, templates, photos, note to cards, a Done you can find |
| [047-you-and-themes](047-you-and-themes.md) | approved | You on one screen, search, new settings, backup, custom themes shared by code and QR |
| [048-lar-chat](048-lar-chat.md) | approved | LAR's chat, round four: the cube pours into it, the sky header, his real steps as a pixel trace, suggestions that follow the day |

Decisions behind them: [ADR 0004](../adr/0004-landing-renders-in-rust-wasm-tiles.md) and [ADR 0005](../adr/0005-portals-are-first-class.md).

## Reference material

`reference/` holds the visual prototype and the capture guide. Raw SIS and Mabini captures and third-party art stay local in `reference/private/`, which git ignores. See [reference/README.md](reference/README.md).

The working plan that produced these specs is [PLAN-landing-login.md](PLAN-landing-login.md).
