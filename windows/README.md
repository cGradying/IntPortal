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

`PUPSISPortal.App` targets `net8.0-windows` and needs the Windows App SDK's XAML
compiler, which only runs on actual Windows — that's why it's kept **out** of
`PUPSISPortal.slnx` (that solution is the mac-buildable Core+Tests subset). It
was authored on macOS where it's never been compiled — expect to fix small
WinUI/WebView2 API details on the first real build.

### 1. Get a Windows machine

Windows 11, or Windows 10 22H2+ (`TargetPlatformMinVersion` in the csproj is
`10.0.17763.0`, but Mica/the newer WinUI visuals want 11). A VM is fine for a
first build/smoke-test pass.

### 2. Install the toolchain

**Visual Studio 2022 (Community is free)** — [visualstudio.microsoft.com](https://visualstudio.microsoft.com/).
In the installer, check these workloads:
- **.NET desktop development**
- **Windows application development** (this is the one that pulls in the
  Windows App SDK project system, the WinUI 3 XAML compiler, and a matching
  Windows 10/11 SDK — trying to assemble those by hand outside VS is the
  fragile path, not recommended for a first build)

This also installs a matching .NET SDK; if you'd rather manage that yourself,
grab the [.NET 8 SDK](https://dotnet.microsoft.com/download) separately first.

**WebView2 Runtime** — ships in the box on Windows 11 and Windows 10 22H2+
(it's the Edge engine). If a fresh Windows 10 install is missing it, grab the
Evergreen Bootstrapper from [Microsoft's WebView2 page](https://developer.microsoft.com/microsoft-edge/webview2/).

### 3. Get the code

```powershell
git clone https://github.com/cGradying/PUPSISPortal.git
cd PUPSISPortal
```

(Or `git pull` if the repo's already there.) No solution edits needed —
`PUPSISPortal.App.csproj` already references `PUPSISPortal.Core` directly, so
building/running the app doesn't require adding it to `PUPSISPortal.slnx`.

### 4. Restore and build

```powershell
dotnet restore windows\PUPSISPortal.App\PUPSISPortal.App.csproj
dotnet build   windows\PUPSISPortal.App\PUPSISPortal.App.csproj -c Release
```

This is where the first-build fixups happen. Expect a handful of small WinUI
API mismatches (a type in the wrong namespace, a control property that moved) —
none of it is architectural, all of it is "authored blind against docs, never
compiled." Fix, rebuild, repeat.

### 5. Run it for dev/testing

Either open `windows/PUPSISPortal.App/PUPSISPortal.App.csproj` directly in
Visual Studio and hit **F5**, or from the CLI:

```powershell
dotnet run --project windows\PUPSISPortal.App\PUPSISPortal.App.csproj
```

This runs unpublished, straight from `bin/`, against the live PUP SIS — sign in
with a real account to verify the scrape/parse/calendar pipeline end to end.

### 6. Publish a shippable `.exe`

See [Packaging](#packaging-windows-only) below for the self-contained publish
command and where the `.exe` lands.

### 7. First launch

The exe is unsigned (no code-signing certificate, same situation as the mac
`.dmg`), so **Windows SmartScreen** will block a double-click the first time:
**"Windows protected your PC" → More info → Run anyway.** That's expected, not
a broken build — the mac equivalent is the Gatekeeper right-click-open dance.
`PasswordVault` will also prompt once on first credential save/read, the same
way the macOS Keychain does.

## Status

State audit (2026-08-14) — source of truth is the code, not memory:

| Stage | What | State | Verified |
|---|---|---|---|
| 0 | Repo scaffold, isolation from the mac build | Built | mac (`dotnet build` green) |
| 1 | Portable Core — parsers, geometry, stores, `Preferences`, `ICSExporter`, `GoogleCalendarClient` | Built | mac, **185 xUnit tests green** |
| 2 | `SisSession` scrape orchestration behind `ISisWebView` | Built | mac, mock-tested (no live site) |
| 3 | `WebView2SisWebView` driver + `PasswordVaultCredentialStore` | Scaffolded | **Unverified** — never compiled |
| 4 | Week-grid `CalendarView` | Scaffolded | **Unverified** |
| 5 | Mica + custom-titlebar shell | Scaffolded | **Unverified** |
| 6 | Notes (`NotesPage`/`NotesView`, vault tree) | Scaffolded, **known bug** (§ below) | **Unverified** |
| 7 | Grades (`GradesView`, trend chart) | Scaffolded | **Unverified** |
| 8 | Integrations (Google OAuth, `.ics`, toast, tray, startup) | Scaffolded | **Unverified** |
| 9 | Packaging (publish command documented) | Documented, no CI yet | N/A |

**Known bug (blocks Stage 6 from working at all):** `NotesView.NavigateShell()`
inlines the 1.88MB `bundle.js` into `CoreWebView2.NavigateToString`, which caps
around 2MB — near-certain failure. Fix in flight: serve the notes-editor folder
over a virtual host instead of inlining it.

**Scope cuts** (deliberate, not bugs — see the Stage 6–8 notes below for why):
notes is one editor pane with no tab strip and no per-class/day/event wiring from
the calendar; grades trend only plots locally-cached terms, no SIS backfill; no
subject-color picker UI; MSIX packaging deferred in favor of a self-contained zip.

Detail, stage by stage:

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
zip that folder for a GitHub release asset (`PUPSISPortal-Windows-1.1.2.zip`,
alongside the mac `.dmg`). Repeat for `win-arm64` if shipping ARM64 too.

MSIX (auto-update, cleaner install, Start-menu shortcut) is a stretch goal, not
required to ship: it needs a Windows Application Packaging Project added in
Visual Studio (a `.wapproj`, which `dotnet` alone can't scaffold) plus a signing
certificate. Revisit if the zip distribution turns out to be annoying in
practice — not before.

Version is set by hand in `PUPSISPortal.App.csproj` (`<Version>`), kept in step
with the mac app's `Scripts/make_dmg.sh` version; there's no shared source
between the two toolchains.
