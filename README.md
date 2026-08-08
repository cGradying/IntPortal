# PUPSISPortal

Native macOS app that signs into the [PUP Student Information System](https://sis8.pup.edu.ph/student/)
**headlessly** and renders the student's own schedule and grades as a native
SwiftUI interface. The SIS web UI is never shown — a hidden `WKWebView` holds
the authenticated session and runs the scraping JavaScript; everything the user
sees is drawn natively.

Sibling to [PUPSIS](https://github.com/cGradying/PUPSIS) (which only auto-fills
the real site). PUPSISPortal is the one with its own interface: a weekly
calendar, a day agenda, Calendar.app sync, reminders, grades with a computed GPA
and a cross-term trend, and a menu-bar presence.

Scope is strictly the signed-in user's own account and data, personal
non-commercial use.

---

## Requirements

- **macOS 14+**. On **macOS 26** the UI uses Liquid Glass (`glassEffect`); on
  14–15 those surfaces fall back to a plain material, so it builds and runs
  there too — the glass look just degrades.
- A Swift toolchain matching your macOS (Xcode 16+ for macOS 14–15; Xcode 26+
  to get the Liquid Glass look on macOS 26).

## Build & run

```sh
swift build -c release                 # build
swift test                             # parser/store/logic tests
Scripts/make_signing_identity.sh       # one-time: stable local signing identity
Scripts/make_mac_app.sh                # package + install to ~/Applications
```

`make_mac_app.sh` builds the release binary, assembles `PUPSISPortal.app`
(bundle id `com.cgradying.pupsisportal`) with a generated `Info.plist` and icon,
code-signs it, and installs to `~/Applications` (pass a directory to install
elsewhere).

### Signing note

`make_signing_identity.sh` creates a stable **self-signed** code-signing
identity in the login keychain. Without it, `make_mac_app.sh` falls back to
ad-hoc signing, whose code identity changes every build — which invalidates the
Keychain ACL for the saved credentials and makes the first post-build launch
block on a `SecurityAgent` prompt before drawing a window. Run it once and click
**Always Allow** on the first launch after.

## Architecture

Pure SwiftPM, no Xcode project. One executable target (`Sources/PUPSISPortalApp`)
plus a test target. ~single-window SwiftUI app; no view-model layer.

### Session & data (`Core/`)

| File | Role |
|---|---|
| `PortalController.swift` | Owns the single hidden `WKWebView`. Headless sign-in, navigation-settling, and schedule/grades loading. `@MainActor`, `WKNavigationDelegate`. |
| `SISScraper.swift` | The scraping JavaScript. A shared table walker maps header cells to output keys by name (positional fallback); Schedule and Grades share it. Also reads/drives the grades School-Year/Semester `<select>`s. |
| `ScheduleParser.swift` | Scraped rows → `[ClassSession]`. Day/time tokenizing lives here. |
| `GradesParser.swift` | Rows → `[SubjectGrade]` + `GradeReport`; units-weighted GPA, term identity, `completedUnits`. |
| `Models.swift` | `Weekday`, `ClassSession`. |
| `DayAgenda.swift` | Pure "today right now" reading (phased items + tomorrow's first), shared by the Today screen and the menu bar. |
| `NextClass.swift` | "What's next" logic and its countdown phrasing. Pure, no clock of its own. |
| `KeychainStore.swift` | Credentials in the Keychain, service `ph.edu.pup.sis8.portal`. |
| `ScheduleStore.swift` / `GradesStore.swift` | Offline JSON caches under Application Support (dir `0700`, file `0600`), loaded synchronously at init so the first frame already has content. `GradesStore` also holds the per-term GPA history. |
| `Preferences.swift` | Theme, per-subject colors, per-week/per-term `SessionStatus`, calendar/export settings, notification prefs, program-total units. `UserDefaults`, injectable for tests. |
| `Theme.swift` | `Palette` (a value injected via `\.palette`), `ThemeChoice`, the `Motion` animation vocabulary, `Theme.Typo` type scale, `Color` hex round-trip. |
| `CalendarBridge.swift` / `EventEditor.swift` | The single `EKEventStore`: reads the visible week, writes/exports events; every mutation routes through `EventEditor` so undo has one hook. |
| `Notifier.swift` | One weekly-repeating `UNCalendarNotificationTrigger` per meeting, rebuilt on any change. |
| `LoginItem.swift` | `SMAppService.mainApp` register/unregister so reminders survive a full quit. OS status is the source of truth. |
| `GridGeometry.swift` / `TimeSnap.swift` / `DayBlock.swift` / `MonthLayout.swift` | Point↔(day,minute) math, quarter-hour snapping, the flat render model + overlap layout, and the year grid. |

### Views (`Views/`)

Weekly grid (`WeekGrid`, `Blocks`, `GridInteractionLayer`), the now-line
(`NowLine`, a `TimelineView` minute clock), year view (`YearView`), the Today
agenda (`AgendaView`), Grades + GPA trend (`GradesView`, SwiftUI Charts),
Settings (`SettingsView`), the menu bar (`MenuBarPanel`), event editing
(`EventEditorPopover`, `SelectionBar`), and sign-in (`CredentialsView`).

## Features

- **Instant, offline-first** — launches straight from the cache, then refreshes
  in the background. A failed refresh keeps the cached calendar and shows a
  quiet staleness note instead of an error screen.
- **Weekly calendar + year view** with a live now-line.
- **Today agenda** — the class in session, what's done, upcoming countdowns,
  free gaps, and a tomorrow preview.
- **Class status** — mark each meeting in-person / online / vacant, per week or
  per whole term; online meetings get a colored strip.
- **Two-way Calendar.app sync** (EventKit) — draw your other calendars beside
  class, and export classes into a chosen calendar (tagged `[PUPSISPortal]` so a
  re-export only touches ours), with per-week/per-status calendar routing.
- **Direct Google Calendar export** — writes classes straight to Google over the
  Calendar API (PKCE OAuth, no client secret), for when macOS's Google/CalDAV
  bridge won't take repeating events. One-time setup in Settings → Google
  Calendar: at [Google Cloud Console](https://console.cloud.google.com) create a
  project, enable the Google Calendar API, add yourself as a Test user, create an
  **iOS** OAuth client (bundle id `com.cgradying.pupsisportal`), and paste its
  Client ID. Re-export replaces only events this app wrote (tagged in
  `extendedProperties`). Also **`.ics` export** for importing anywhere.
- **Reminders** — a configurable lead-time notification before each class;
  optional **Start at login** so they fire even when the app is fully quit.
- **Menu bar** — next class + a today-at-a-glance mini-agenda, always visible.
- **Grades & GPA** — units-weighted GPA, a **cross-term GPA trend** backfilled by
  driving the grades page's SY/Semester dropdowns, and units-completed progress.
- **Themes** — PUP Maroon, Ivory, Astra Moon, or Match System; per-subject color
  overrides.

## Testing

```sh
swift test
```

Parser, store, GPA/history, and day-agenda logic are unit-tested with real
scraped-shape fixtures (never real personal data). UI and live SIS/EventKit
integration are verified by running the packaged app.

## Security

- Credentials live **only** in the macOS Keychain
  (`security find-generic-password -s ph.edu.pup.sis8.portal`) — never on disk,
  in logs, or in commits.
- Cached schedule/grades are the student's own data: Application Support, file
  mode `0600`, erased on sign-out.
- Nothing is sent anywhere but the real PUP SIS server, and only the signed-in
  user's own pages are read. No other students' data, no auth bypass.

---

<div align="center">

[![Author: cGradying](https://img.shields.io/badge/cGradying-AUTHOR-10B981?style=for-the-badge&labelColor=0B1120)](https://github.com/cGradying)

</div>
