# 052 Try it in the browser

**Status:** shipped at /try on the website.

## What changes for the student

Anyone, on any phone or computer, opens `/try` on the website and is inside the real app on demo data: Today, Schedule, Grades, Study, notes, deadlines, LAR's nudges. Nothing is installed, nothing is sent anywhere, and nothing they change is kept after they leave. It is the same Look around the app has on its sign-in page.

## Direction and references

- Look around first (010 C39) is already the whole app on made-up data. The browser has no Tauri shell, so the shell's commands need another home there.
- The Rust core holds the logic (today, the coach, deadlines, the week, study). The browser demo runs that same core, compiled to WebAssembly, so the demo can't drift from the app.

## Keep

- The app's screens, untouched. The demo is the app's own build with a different shell underneath.
- Demo data from `src-tauri/src/demo.rs`, moved where both shells can use it.

## Behaviour

- **C1.** `crates/intportal-web` compiles to `wasm32-unknown-unknown`. It holds the demo account in memory and answers the app's commands with the same core functions the Tauri shell calls.
- **C2.** `pnpm build:web` builds the app for the browser: the Tauri `invoke` is answered by the WebAssembly module through `mockIPC`, and the app opens straight into the demo, with the portal's dive.
- **C3.** Reads answer as on the phone: Today, the coach, deadlines, the week, standing, study, decks, notes, reminders.
- **C4.** Writes work for the visit and are gone on reload: ticking Done, marks and moves, colours, notes, deck reviews and new decks, own deadlines.
- **C5.** What needs the phone says so in one line and doesn't break the screen: sign-in, sync, eMabini, the camera and scan, photos, the calendar, backups, notifications, the Live Activity, haptics and IntAssis. The line is "That works in the app. Get it on the download page." with a link to `/download`.
- **C6.** It runs in current Safari, Chrome, Firefox and Edge, on phones and computers. On a wide screen the app sits in a phone-sized frame in the middle of the page; on a phone it fills the screen.
- **C7.** The demo sends nothing: no network request after the page's own files load.
- **C8.** The WebAssembly module is at most 3 MB gzipped. The page is usable within 3 seconds on a mid-range phone on 4G.

## Copy

- The banner above the frame on wide screens: "This is IntPortal on demo data. Nothing you change is kept."
- C5's line, exactly as written there.

## Data shape

- `crates/intportal-web/src/lib.rs`: `#[wasm_bindgen] fn call(cmd: &str, args: JsValue) -> Result<JsValue, JsValue>`.
- `src/lib/web.ts`: installs `mockIPC` in a web build only (`import.meta.env.VITE_WEB`).
- The demo data moves from `src-tauri/src/demo.rs` to `crates/intportal-core/src/demo.rs`.

## Errors

- WebAssembly unavailable or the module fails to load: the page shows the app's screenshots and a link to `/download`, "Your browser couldn't open the demo."

## Motion and Reduce Motion

As in the app.

## Accessibility

As in the app. The frame on wide screens doesn't trap focus.

## Out of scope

- Signing in to the real SIS from a browser. PUP's sites don't allow it from another origin, and a proxy would be a server holding logins (ADR 0002).
- Installing the demo as a web app.

## Test map

| Criterion | Check |
|---|---|
| C1 | `cargo build -p intportal-web --target wasm32-unknown-unknown` in CI |
| C3, C4 | `cargo test -p intportal-web` calls each command on the demo account |
| C2, C5, C6 | `/try` at 375 and 1440 px in the browser pane (Chromium) |
| C7 | the network log of `/try`: every request is to the site itself |
| C8 | `intportal_web.wasm` is 1.5 MB, 506 KB gzipped |

## Open questions

None. If the store can't be made to run in WebAssembly, C1 falls back to an in-memory store behind the same `Store` methods, and this spec records it.
