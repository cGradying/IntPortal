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

## Status

Stage 0 (scaffold) done. See `.claude/plans/windows-port-stages.md` for the full
staged plan. Owned by the `pupsis-windows` agent; the mac agents never touch this
folder.
