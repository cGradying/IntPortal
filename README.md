# PUPSISPortal

Native macOS app that signs into the [PUP Student Information System](https://sis8.pup.edu.ph/student/)
**headlessly** and renders your own schedule and grades as a native SwiftUI
interface. The SIS web UI is never shown — a hidden `WKWebView` holds the
authenticated session and runs the scraping JavaScript; everything you see is
drawn natively, works offline, and fits macOS.

Sibling to [PUPSIS](https://github.com/cGradying/PUPSIS) (which only auto-fills
the real site). PUPSISPortal is the one with its own interface: a weekly
calendar, a day agenda with notes, Calendar.app + Google Calendar sync,
reminders, grades with a computed GPA and cross-term trend, and a menu-bar
presence.

Scope is strictly your own account and data — personal, non-commercial use,
which is what PUP's Terms of Use permit. It never scrapes other students,
bypasses auth, or redistributes SIS content.

---

## Contents

- [Who it's for / use cases](#who-its-for--use-cases)
- [Install](#install)
- [First launch & sign-in](#first-launch--sign-in)
- [Using the app](#using-the-app)
  - [Navigating](#navigating)
  - [Schedule (week & year)](#schedule-week--year)
  - [Class status: online / vacant](#class-status-online--vacant)
  - [Today & Notes](#today--notes)
  - [Grades & GPA](#grades--gpa)
  - [Calendar sync & export](#calendar-sync--export)
  - [Reminders & menu bar](#reminders--menu-bar)
  - [Appearance](#appearance)
- [Setting up Google Calendar export](#setting-up-google-calendar-export)
- [Build from source](#build-from-source)
- [Architecture](#architecture)
- [Testing](#testing)
- [Security & privacy](#security--privacy)
- [Reviews](#reviews)

---

## Who it's for / use cases

For a PUP student who wants their SIS schedule and grades as a fast, native app
instead of a slow web portal.

- **Open once, glance daily.** Launches instantly from cache to your week grid
  and a "Today" agenda — no waiting on SIS, no re-logging-in.
- **Know what's next.** The now-line, "next class in N minutes", the menu-bar
  mini-agenda, and pre-class reminders keep you on time without opening a browser.
- **Put class on your real calendar.** Export your term into Apple Calendar,
  Google Calendar, or a shareable `.ics` file — repeating weekly, ending on your
  term-end date, and re-exporting cleanly replaces the old copy.
- **Track your standing.** Units-weighted GPA, a cross-term GPA trend, and
  units-completed progress, computed from your posted grades.
- **Adapt to reality.** Mark a meeting online or vacant (for one week or the
  whole term); the grid, exports, and reminders follow.
- **Keep notes with your day.** Attach notes to a class or the day, in plain text
  or Markdown.

---

## Install

Two ways in:

**A. Download a build** (if one is attached to a [Release](https://github.com/cGradying/PUPSISPortal/releases)):
download `PUPSISPortal.app`, move it to `~/Applications`, and open it. Because the
build is self-signed, the first open needs **right-click → Open → Open** (or
System Settings › Privacy & Security › "Open Anyway").

**B. Build it yourself** — see [Build from source](#build-from-source). This is
the recommended path and the one the signing notes below assume.

**Requirements:** macOS 14 or later. On macOS 26 the interface uses Liquid Glass;
on 14–15 those surfaces fall back to a plain material — it still runs, the glass
look just degrades.

---

## First launch & sign-in

1. Open the app. You'll see a sign-in screen (the real SIS site is never shown).
2. Enter your **PUP SIS student number and password**. They're stored only in the
   macOS Keychain and used to hold a session — never written to disk or logs.
3. The app signs in headlessly, scrapes your schedule, and draws the week grid.
   After the first time it launches straight to the cached calendar and refreshes
   in the background.

If a refresh fails (SIS down, no network), the cached calendar stays on screen
with a small "last updated" note instead of an error.

To change accounts: **Settings → Account → Edit Credentials** or **Sign Out**
(sign-out erases the cached schedule and grades).

---

## Using the app

### Navigating

A thin floating pill at the top center switches between **Schedule**, **Today**,
and **Grades** (or press **⌘1 / ⌘2 / ⌘3**). The **gear** (top-right) opens
**Settings** (**⌘,**). On the Schedule screen, the control cluster (week/year,
arrows, add) collapses into an icon — click it to expand.

### Schedule (week & year)

- **Week grid** with a live **now-line** carrying the current time; today's column
  is marked, past blocks dim.
- Switch to **Year** to see the whole term at a glance; click a week to jump to it.
- Move by week/year with the arrows or **⌘[** / **⌘]**; **Today** returns to now.
- **Add and edit your own events** right on the grid: drag to create, drag to
  move, drag an edge to resize, multi-select, duplicate, delete — all with undo.
  Repeating events ask "this event / all future" before changing a series.

### Class status: online / vacant

Right-click a class (or use its menu) to mark it **In person**, **Online**, or
**Vacant** — either **just this week** or for the **whole term**. Online meetings
get a colored strip; vacant ones drop out of the grid (toggle **Show Cancelled**
to bring them back faded). Status flows through to reminders and calendar exports.

### Today & Notes

The **Today** screen reads your day top to bottom: the class in session, what's
done, what's upcoming with a countdown, the **free time** between things, and a
one-line look at tomorrow. It folds in your own events from the calendars you've
ticked, so free-time reflects the whole day.

**Notes** attach here, in one of two styles (Settings → Today Notes):

- **Sidebar** — a plain notes column beside the list.
- **Popup (Markdown)** — tap a class or event to open a note anchored to it, plus
  a **Notes** button for a day scratchpad. Supports Markdown with an **Edit /
  Preview** toggle: `#` headings, `-` bullets, `- [ ]` / `- [x]` task checkboxes,
  and `**bold**` / `*italic*`. Rows that have a note show a dot.

### Grades & GPA

The **Grades** screen shows your posted subjects, a **units-weighted GPA**, a
**cross-term GPA trend** (backfilled by driving the SIS School-Year/Semester
dropdowns), and **units completed**. Grade cells are empty until grades are
posted — that's the normal state most of a semester. Set your program's total
units in **Settings → Grades** for the completed-units progress.

### Calendar sync & export

**Settings → Calendar** (grant access once):

- **Show other calendars** — tick any calendar (Apple, iCloud, or a Google
  account you've added to macOS) to draw its events beside your classes.
- **Export classes** into a calendar you choose, as weekly repeats ending on your
  **Repeat until** date. Online classes can go to their own calendar. Exports are
  tagged, so **re-exporting replaces** the previous copy and leaves your own
  events alone. After the first export, status changes sync automatically.
- **Export `.ics`** — save a standard calendar file to import anywhere (Google
  web, a phone), no calendar access needed.
- For a reliable Google path, use [direct Google export](#setting-up-google-calendar-export)
  below.

### Reminders & menu bar

- **Settings → Notifications** — turn on a reminder a chosen number of minutes
  before each class. Vacant meetings are skipped.
- Reminders fire only while the app is running; enable **Start at login** so they
  fire even after a restart.
- The **menu-bar** item shows your next class and a today-at-a-glance mini-agenda,
  so you can close the window and still stay oriented.

### Appearance

**Settings → Appearance** — themes **PUP Maroon**, **Ivory**, **Astra Moon**, or
**Match System**, plus per-subject color overrides.

---

## Setting up Google Calendar export

The most reliable way to get classes into Google (macOS's built-in Google/CalDAV
sync often refuses repeating events). This writes to Google directly over its API
using **your own** OAuth client — no secrets are shipped, and only your account
is touched.

One-time setup at [Google Cloud Console](https://console.cloud.google.com):

1. Create a **project**.
2. **APIs & Services → Enable APIs** → enable **Google Calendar API**.
3. **OAuth consent screen** → External → add your own Google account as a
   **Test user**.
4. **Credentials → Create credentials → OAuth client ID** → application type
   **iOS**, bundle ID `com.cgradying.pupsisportal`. Copy the **Client ID**
   (ends in `.apps.googleusercontent.com`).
5. In PUPSISPortal: **Settings → Google Calendar (direct)** → paste the Client ID
   → **Connect Google** → approve in the browser → pick a calendar → **Export to
   Google**.

Re-exporting replaces only the events this app wrote. **Note:** while your consent
screen stays in "testing", Google expires the sign-in about **once a week**, so
you'll tap **Connect** again occasionally — that's Google's rule for unpublished
apps, not a bug.

HELLO TEAM RYZZA!!!d fkjenjsncjnsndjejduajd
wdnwjfdnwhjhaedhand
wadjwdjajsdwa
dwdjefjskfpowa

---

## Build from source

Pure SwiftPM — no Xcode project needed, just a Swift toolchain (Xcode 16+ on
macOS 14–15; Xcode 26+ to get the Liquid Glass look on macOS 26).

```sh
swift build -c release                 # build
swift test                             # parser / store / logic tests
Scripts/make_signing_identity.sh       # one-time: stable local signing identity
Scripts/make_mac_app.sh                # package + install to ~/Applications
```

`make_mac_app.sh` builds the release binary, assembles `PUPSISPortal.app`
(bundle id `com.cgradying.pupsisportal`) with a generated `Info.plist` and icon,
code-signs it, and installs to `~/Applications` (pass a directory to install
elsewhere).

### Signing note

`make_signing_identity.sh` creates a stable **self-signed** code-signing identity
in the login keychain. Without it, `make_mac_app.sh` falls back to ad-hoc signing,
whose code identity changes every build — which invalidates the Keychain ACL for
your saved credentials and makes the first post-build launch block on a
`SecurityAgent` prompt before drawing a window. Run it once, and click **Always
Allow** on the first launch after a build.

---

## Architecture

Pure SwiftPM, one executable target (`Sources/PUPSISPortalApp`) plus a test
target. Single-window SwiftUI app; no view-model layer.

### Session & data (`Core/`)

| File                                                                             | Role                                                                                                                                                       |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PortalController.swift`                                                         | Owns the single hidden `WKWebView`. Headless sign-in, navigation-settling, schedule/grades loading. `@MainActor`, `WKNavigationDelegate`.                  |
| `SISScraper.swift`                                                               | The scraping JavaScript. A shared table walker maps header cells to output keys by name (positional fallback); Schedule and Grades share it.               |
| `ScheduleParser.swift` / `GradesParser.swift`                                    | Scraped rows → `[ClassSession]` / `[SubjectGrade]` + `GradeReport` (units-weighted GPA, term identity).                                                    |
| `Models.swift`                                                                   | `Weekday`, `ClassSession`.                                                                                                                                 |
| `DayAgenda.swift` / `NextClass.swift`                                            | Pure "today right now" and "what's next" readings, shared by the Today screen and the menu bar.                                                            |
| `KeychainStore.swift` / `GoogleTokenStore.swift`                                 | SIS credentials and the Google refresh token in the Keychain (service `ph.edu.pup.sis8.portal`).                                                           |
| `ScheduleStore.swift` / `GradesStore.swift` / `NotesStore.swift`                 | Offline JSON documents under Application Support (dir `0700`, file `0600`).                                                                                |
| `Preferences.swift`                                                              | Theme, per-subject colors, per-week/term `SessionStatus`, calendar/export settings, notes style, notification prefs. `UserDefaults`, injectable for tests. |
| `Theme.swift`                                                                    | `Palette` (injected via `\.palette`), `ThemeChoice`, the `Motion` vocabulary, `Theme.Typo` type scale.                                                     |
| `CalendarBridge.swift` / `EventEditor.swift`                                     | The single `EKEventStore`: reads the week, writes/exports events; every mutation routes through `EventEditor` for one undo hook.                           |
| `ICSExporter.swift` / `ClassRecurrence.swift`                                    | `.ics` file export and the shared weekly-`RRULE` builder.                                                                                                  |
| `GoogleAuth.swift` / `GoogleCalendarClient.swift`                                | PKCE OAuth (no secret) and the Calendar REST client for direct Google export.                                                                              |
| `Notifier.swift` / `LoginItem.swift`                                             | Weekly reminder triggers, and `SMAppService` start-at-login so they survive a quit.                                                                        |
| `GridGeometry.swift` / `TimeSnap.swift` / `DayBlock.swift` / `MonthLayout.swift` | Point↔(day,minute) math, snapping, the flat render model, and the year grid.                                                                               |

### Views (`Views/`)

Weekly grid (`WeekGrid`, `Blocks`, `GridInteractionLayer`), the now-line
(`NowLine`), year view (`YearView`), the Today agenda + notes (`AgendaView`,
`NotesPanel`, `MarkdownNotesEditor`), Grades + GPA trend (`GradesView`), Settings
(`SettingsView`), the menu bar (`MenuBarPanel`), event editing
(`EventEditorPopover`, `SelectionBar`), and sign-in (`CredentialsView`).

---

## Testing

```sh
swift test
```

Parsing, stores, GPA/history, day-agenda, Markdown, `.ics`, and the Google event
builder are unit-tested with real scraped-_shape_ fixtures — never real personal
data. UI and live SIS / EventKit / Google integration are verified by running the
packaged app.

---

## Security & privacy

- Credentials live **only** in the macOS Keychain
  (`security find-generic-password -s ph.edu.pup.sis8.portal`) — never on disk,
  in logs, or in commits. The Google **refresh token** is in the Keychain too; the
  client ID is not a secret.
- Cached schedule/grades/notes are your own data: Application Support, file mode
  `0600`, erased on sign-out.
- Nothing is sent anywhere but the real PUP SIS server and — only if you set it up
  — your own Google Calendar. Only your own pages are read: no other students'
  data, no auth bypass.

---

## Reviews

_Feedback from people using the app will go here._

> _"…"_

---

<div align="center">

[![Author: cGradying](https://img.shields.io/badge/cGradying-AUTHOR-10B981?style=for-the-badge&labelColor=0B1120)](https://github.com/cGradying)

</div>
