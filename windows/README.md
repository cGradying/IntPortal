# PUPSISPortal — Windows port

The **C#/.NET + WinUI 3** Windows version, living in this repo under `windows/`,
isolated from the macOS SwiftPM app so the two toolchains never collide:
SwiftPM only reads `Sources/`+`Tests/`, and `dotnet` only touches `windows/`.

## Projects

| Project | Target | Builds where | Role |
|---|---|---|---|
| `PUPSISPortal.Core` | net8.0 | **mac + Windows** | All portable logic — parsers, geometry, stores, models, scrape orchestration behind `ISisWebView`. No UI, no platform APIs. |
| `PUPSISPortal.Core.Tests` | net8.0 | **mac + Windows** | xUnit tests. The parser is the real logic; it's covered here with the mac app's real fixtures. |
| `PUPSISPortal.App` | net8.0-windows | **Windows only** | WinUI 3 UI + platform glue (WebView2, PasswordVault, toast). Added on a Windows box — its templates need the Windows App SDK. |

## Build / test (macOS dev)

```sh
dotnet build windows/PUPSISPortal.slnx
dotnet test  windows/PUPSISPortal.slnx
```

Only the .NET 10 runtime is on the dev mac, so the net8.0 test host rolls forward
(`<RollForward>Major</RollForward>` in the test csproj). On Windows, with the
net8.0 runtime present, that's a no-op.

## Shared assets

- `assets/sis-scrapers/*.js` — the SIS scraping scripts, extracted verbatim from
  the macOS app's `Core/SISScraper.swift`. The App runs these in WebView2 via
  `ExecuteScriptAsync`. Keep them in sync if the mac scrapers change.
- The notes editor bundle is **not** duplicated here — the App build copies
  `notes-editor.bundle.js` from the repo's existing build output (wired at the
  notes stage), rather than committing a second copy of a generated file.

## Building the WinUI app (Windows only)

`PUPSISPortal.App` targets `net8.0-windows` and needs the Windows App SDK, so it
is **not** in `PUPSISPortal.slnx` (that keeps the mac build of Core+Tests green).
On Windows:

```powershell
dotnet build windows/PUPSISPortal.App/PUPSISPortal.App.csproj
```

or add it to the solution and open in Visual Studio. It was authored on macOS
where it can't be compiled — expect to fix small WinUI/WebView2 API details on the
first Windows build.

## Status

- **Stages 0–2 done, tested on mac (185 xUnit tests):** the whole portable Core +
  the `SisSession` scrape orchestration behind `ISisWebView`.
- **Stages 3–9 scaffolded (Windows-only, unverified — first Windows build will
  need fixups):**
  - **3–5** — WebView2 `ISisWebView` driver + PasswordVault creds, a Mica +
    custom-titlebar shell, a week-grid `CalendarView`.
  - **6 — Notes:** `NotesPage`/`NotesView` host the mac app's
    `notes-editor.bundle.js` **verbatim** in WebView2 (`assets/notes-editor/`),
    bridged through a small `window.webkit` shim so the bundle's WKWebView-style
    `postMessage` calls land on `chrome.webview.postMessage` unmodified. Native
    vault tree (add/rename/delete). Scope cut: one editor pane, no multi-note tab
    strip (the mac app's closeable-tabs bar isn't ported); no per-class/day/event
    notes wiring from the calendar yet.
  - **7 — Grades:** `GradesView` — summary, GPA trend, units, term picker,
    subject rows. Trend is drawn on a plain `Canvas`/`Polyline` (no chart
    library) rather than Swift Charts. It only plots terms already in the local
    history cache — the mac app's "Load past terms" backfill needs a
    navigate-and-rescrape primitive `SisSession`/`ISisWebView` don't expose yet
    (noted in `SisSession.cs`).
  - **8 — Integrations:** loopback-redirect PKCE Google OAuth (`HttpListener`
    on an ephemeral 127.0.0.1 port — Windows has no scheme-registration-free
    equivalent of `ASWebAuthenticationSession` for an unpackaged exe), refresh
    token in `PasswordVault`, `.ics` export via `FileSavePicker`, class-start
    toast reminders (`AppNotificationManager`, app must be running — same limit
    as mac), a tray icon (raw `Shell_NotifyIcon` + a classic `WndProc` subclass,
    since WinUI 3 has no tray API), "Start with Windows" (HKCU Run key — the
    MSIX-only `StartupTask` API doesn't apply to an unpackaged exe). Closing the
    window hides it instead of quitting; the tray's Exit is the real quit. Cut:
    no per-subject color picker UI (no settings screen exists yet to hold one).
  - **9 — Package:** see below.
- Ownership: `pupsis-windows`. See `.claude/plans/windows-port-stages.md`.

## Packaging (Windows only)

No MSIX yet — matching the `WindowsPackageType=None` dev setup, the simplest
real distribution is a self-contained publish, zipped:

```powershell
dotnet publish windows/PUPSISPortal.App/PUPSISPortal.App.csproj `
  -c Release -r win-x64 --self-contained -p:PublishSingleFile=false
```

Output lands in `PUPSISPortal.App/bin/Release/net8.0-windows.../win-x64/publish/`;
zip that folder for a GitHub release asset (`PUPSISPortal-Windows-1.1.1.zip`,
alongside the mac `.dmg`). Repeat for `win-arm64` if shipping ARM64 too.

MSIX (auto-update, cleaner install, Start-menu shortcut) is a stretch goal, not
required to ship: it needs a Windows Application Packaging Project added in
Visual Studio (a `.wapproj`, which `dotnet` alone can't scaffold) plus a signing
certificate. Revisit if the zip distribution turns out to be annoying in
practice — not before.

Version is set by hand in `PUPSISPortal.App.csproj` (`<Version>`), kept in step
with the mac app's `Scripts/make_dmg.sh` version; there's no shared source
between the two toolchains.
