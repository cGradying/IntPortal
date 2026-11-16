# Architecture

How IntPortal is put together and what must stay true. Read it with [CONTEXT.md](../CONTEXT.md), which explains the app's terms.

## Layers

```
 Svelte UI           src/                  screens, one shared store
     |  invoke("command")
     v
 Tauri shell         src-tauri/src/        commands, keychain, store opening
     |  plain Rust calls          \
     v                             Native plugins   plugins/
 Core                crates/intportal-core    glance (widget, Live Activity / Update),
   SIS client, schedule, grades,               calendar, camera
   study, notes, encrypted store
```

Each layer only calls the one below it. The core has no UI and no platform code, so all of its logic is tested with `cargo test` on any machine. The shell is thin: it turns commands into core calls and owns the few things that need the phone. The UI holds no domain rules; it asks the core and draws the answer.

Other crates: `intportal-ai` and `intportal-llm` (the optional on-device assistant, below) and `intportal-tiles` (the landing portal, compiled to a 69 KB WebAssembly file by `scripts/tiles.sh`).

## The core, module by module

| Module | What it does |
|---|---|
| `portal.rs` | The portal registry: each PUP system the app opens (SIS, Mabini, and placeholders), with its status, theme, sign-in fields, limits and keychain service. |
| `sis/` | The SIS client (`client.rs`), the live-host probe (`host.rs`), HTML scraping (`scrape.rs`), and the sign-in guard (`guard.rs`): one credential POST per tap, a `Ledger` of tries per 15 minutes, no retry after a rejected login. |
| `mabini/` | The eMabini (Moodle) client: login with its `logintoken`, the `sesskey`, the AJAX calls for courses and deadlines, and the grade overview table (`parse.rs`). |
| `schedule.rs` | Turns scraped schedule rows into `ClassSession`s. |
| `grades.rs` | Grade parsing, GPA, goals and `Standing` (what you need on the rest). |
| `today.rs` | The agenda for a moment: up next, free time, marks and moves, busy spans, reminders, the glance line. The largest module. |
| `coach.rs` | Picks LAR's one nudge from signals. |
| `study.rs` | Decks, cards and FSRS scheduling, answer checks, distractors, the streak. |
| `syllabus.rs` | Parses a pasted course outline into items, and the grade tally. |
| `notes.rs` | Notes per class or per day, and their Markdown export. |
| `calendar.rs` | `.ics` export and the class events written to the phone's calendar. |
| `campus.rs` | Resolves a student number to a campus. |
| `model.rs` | Shared types: `ClassSession`, `Weekday`. |
| `store.rs` | The SQLCipher store, one file per student. `Snapshot` holds the SIS data, marks, colours, goals and plans. Notes, decks and study stats have their own tables, Mabini's data is saved apart from the `Snapshot` (`save_mabini`), and the AI keeps its chat (`turns`) and search index (`chunks`) here too. |

## The shell

`src-tauri/src/lib.rs` holds the app state (the open store, the signed-in SIS and Mabini clients, one sign-in guard per portal) and registers every command. Commands live in `src-tauri/src/commands/`, one file per area. Beside them are the keychain, the saved logins (one keychain entry per portal), one random database key per store file, and the sample student behind **Look around first**. A store its key can't open is renamed `.locked-<time>` and a fresh one starts, so the app never bricks and never deletes.

## The interface

- `src/routes/+page.svelte` boots the app and shows the landing or the five tabs.
- `src/lib/state.svelte.ts` is the one shared store. Screens read it; only this file writes it.
- `src/lib/api.ts` wraps each command in a typed function. `scripts/commands-check.mjs` fails CI when the commands and these wrappers drift apart.
- `src/lib/screens/` holds Today, Schedule, Grades, Study and You.
- A new student first meets LAR in `src/lib/welcome/Talk.svelte`, then the landing's portal (`Landing.svelte`).
- The In session picture is a small shader scene per campus (`src/lib/campus/`), loaded only for the student's campus.
- All motion comes from one set of helpers and timings in `src/lib/motion.ts`, and Reduce Motion is honoured everywhere.

## Main flows

- **Sign in.** The shell sends one login request per tap through a guard: at most three tries per 15 minutes per portal, and no automatic retry after a rejected password, so the app can't get a PUP account locked. A good login is saved to the keychain, the student's store opens, and the schedule and grades load.
- **Sync.** `syncNow()` signs in again from the saved login if the session expired, through the same guard. A failed grades page keeps the last grades.
- **Every minute.** `refreshToday()` rebuilds Today, then sends the next class to the widget and the class card on the Lock Screen (iOS Live Activity, Android Live Update). The student chooses in You › Reminders whether the card always shows, shows only after leaving the app, or never.
- **Reminders.** Notifications are replaced with the next week's on each launch and sync.
- **Scan.** A photo's text is read by the phone's recognizer and cleaned in Rust. With the assistant installed, LAR also tidies it, and his version is kept only if every number, code and date is unchanged.

## The optional assistant

LAR's chat runs a small model with llama.cpp, on the phone, only after the student chooses to download one ([ADR 0003](adr/0003-on-device-ai-llama-cpp.md)). `intportal-ai` is pure Rust (prompts, schemas, search over notes) and is tested with a fake model. `intportal-llm` runs the real model and downloads it. The assistant never changes anything itself: it shows a confirm card, and tapping Apply calls the normal commands. More in [ai.md](ai.md).

## Invariants

- **Data stays on the phone.** No backend and no sync between devices until the cloud tier ([ADR 0002](adr/0002-device-only-data.md)).
- **Only the student's own account.** That is what PUP's terms allow.
- **Logins are in the keychain**, one service per portal, never in the store, logs or localStorage.
- **No portal can get a student locked out.** Every sign-in goes through the guard: one POST per tap, at most three tries per 15 minutes per portal, no automatic retry after a rejection.
- **Portals don't share state.** A Mabini failure never fails an SIS sync, and the reverse.
- **Each student's store is SQLCipher-encrypted** with its own key in the keychain. A store that won't open is set aside, never deleted.
- **The core stays pure.** No platform APIs in `intportal-core`; anything that needs the phone goes in the shell or a plugin.
- **LAR speaks.** He is the only character. Copy follows `PRODUCT.md` and `DESIGN.md`.
- **Reduce Motion is honoured** everywhere, including the landing.
- **Anything that opens over the page registers its close with `closable()`**, so Android's back gesture closes it and not the app.

## iOS and Android

Both run the same Rust and the same Svelte. They differ only in the shell and the plugins:

| | iOS | Android |
|---|---|---|
| Keychain | Keychain Services (`keyring`) | Keystore-sealed values (`Secrets.kt`) |
| Store encryption | SQLCipher on CommonCrypto | SQLCipher on vendored OpenSSL |
| Next class outside the app | Live Activity, widget (widget needs a paid team for App Groups) | Live Update in the status bar, widget |
| Scanner | Vision | ML Kit through Google Play services (not bundled, to keep the APK small) |
| Release build | `scripts/phone.sh`, release by default | `scripts/emu.sh --release`: arm64 only, R8 and resource shrinking, signed APK and AAB |
| Calendar | EventKit | CalendarContract |
| Native project | `gen/apple`, generated from `project.yml` | `gen/android`; see `docs/android.md` |

Desktop `cargo` builds compile neither the Swift nor the Kotlin. Only `scripts/sim.sh` and `scripts/emu.sh` prove them.

## Size

Small and fast is a requirement. The Android APK is 22.3 MB and the iPhone release 18 MB installed. The release profile in the root `Cargo.toml` turns on link-time optimisation and optimises for size, keeping full speed only for SQLite and llama.cpp. `src-tauri` builds only `staticlib` and `cdylib`, because an `rlib` output makes Cargo skip LTO. Android builds for arm64 only, the text scanner comes from Google Play services, and each campus scene and the AI model download only when needed.

## Decisions

- [0001](adr/0001-tauri-rust-svelte.md) Tauri, Rust and Svelte.
- [0002](adr/0002-device-only-data.md) Student data stays on the device.
- [0003](adr/0003-on-device-ai-llama-cpp.md) On-device AI runs llama.cpp in Rust; local only.
- [0004](adr/0004-landing-renders-in-rust-wasm-tiles.md) The landing renders in Rust/WASM tiles.
- [0005](adr/0005-portals-are-first-class.md) Portals are first-class: SIS and Mabini (eMabini) are ready.

## Known gaps

- `src/lib/api.ts` types are written by hand to match the Rust structs, so a changed field isn't caught until runtime (#61).
- The SIS parsers have no fixtures from real pages, so a change on PUP's side shows up only on a phone.
- `You.svelte` and a few other screens are 700 to 1,000 lines and could be split (#64).
- Screens are checked by hand on the simulator and emulator.
