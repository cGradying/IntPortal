# Architecture

How IntPortal is put together, where each thing lives, and what must stay true. Read it with `CONTEXT.md` (the app's terms) and `docs/TEAM.md` (who owns what).

## Layers

```
 Svelte UI            src/                    screens, components, app state
     |  invoke("command")        invoke("plugin:<name>|<command>")
     v                                    v
 Tauri shell          src-tauri/src/lib.rs     Local plugins   plugins/
   AppState, commands, keychain,               glance: widget, Live Activity / Live Update
   store opening, demo                         calendar: EventKit / CalendarContract
     |  plain Rust calls                       (Swift and Kotlin halves)
     v
 Core                 crates/intportal-core    domain logic, SIS client, SQLCipher store
     |
     v
 Device               keychain or Keystore, notifications, biometrics, haptics, calendar
```

Each layer only calls the one below it. The core has no UI and no platform APIs, so all of its logic runs under `cargo test` on any machine. The shell is thin: it turns commands into core calls and owns the few things that need the platform (the keychain, the store's key, the data folder). The UI holds no domain rules; it asks the core and draws the answer.

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

`src-tauri/src/lib.rs` holds `AppState` (the open `Store`, the data folder, the signed-in `SisClient` and `MabiniClient`, and one guard `Ledger` per portal) and 43 commands; the 16 AI commands are in `src-tauri/src/ai.rs`. All are registered in `run()` with `generate_handler!`. It also holds:

- `keychain`, the platform keychain (Keychain Services on Apple, a Keystore-sealed value on Android through `Secrets.kt`);
- `vault`, the saved logins, one keychain service per portal (`Portal.keychain_service`);
- the guard ledgers, saved as `login-guard.json` (SIS) and `mabini-guard.json` in the app's data folder, outside any student's store, so a restart doesn't reset the count;
- `dbkey`, one random 32-byte key per store file, kept in the keychain;
- `open_store`, which opens a student's store with its key. A store the key can't open is renamed `.locked-<time>` and a fresh one starts, so the app never bricks;
- `DEMO`, the flag behind **Look around with demo data**.

Every command returns `Result<T, String>` today.

## The interface

- `src/routes/+page.svelte` boots the app: it reads `has_login` and `snapshot`, adopts the snapshot, starts the clock, then shows the landing or the five tabs.
- `src/lib/state.svelte.ts` is the one shared store, `app`. Screens read it; only this file writes it.
- `src/lib/api.ts` wraps each command in a typed function. Its types are written by hand to match the Rust structs.
- `src/lib/screens/` holds Today, Schedule, Grades, Study and You. Sheets and pages that open over them (`ClassSheet`, `SubjectPage`, `DeckPage`, `NoteEditor`) live in `src/lib/`.
- The landing is `Landing.svelte` and `PortalStage.svelte`. `landing.ts` is its timeline as a pure function of time, `portal3d.ts` the three.js scene, `pentomino.ts` the baked frame. These are being replaced by a Rust/WASM tile renderer and a portal registry; see `docs/specs/010-landing.md`, `011-login.md`, `012-portals.md` and ADRs 0004 and 0005. Until those ship, the lines above describe the code.
- `src/lib/lar/` is LAR: pure sprite grids and the component.

## Main flows

**Sign in.** `Landing` sends the login to `sign_in`. The shell signs in with `sign_in_guarded`: plain GETs find a live SIS host, then exactly one credential POST, counted in the ledger. It saves the login to the vault, opens that student's store (`open_account`), pulls the schedule and grades (`refresh`), and returns the `Snapshot`. The UI calls `adopt(snapshot)`.

**Adopt.** `adopt()` in `state.svelte.ts` stores the snapshot, then refreshes notes, Today, the reminders and the phone's IntPortal calendar. Every path that gets a new snapshot (sign-in, sync, an edit, demo) goes through it.

**Sync.** `syncNow()` calls `sync`, which signs in again from the vault when the session expired, through the same guard, and never while the saved login is marked rejected. A failed grades page keeps the last grades; only a signed-out session fails the whole sync.

**Mabini.** `mabini_sign_in` signs in to eMabini through Mabini's own ledger and keychain entry, then pulls courses, deadlines and grades; `mabini_sync` refreshes them. Today shows the deadlines next to the syllabus ones (`MabiniDue`), and You shows Mabini's account apart from the SIS.

**The minute tick.** `startClock()` runs `refreshToday()` on each minute boundary. It reads the student's own calendar events as busy time when that setting is on, asks `today` for the agenda, and pushes the next class and the glance line to `plugin:glance|update` (widget and Live Activity on iOS, Live Update on Android).

**Coach.** Today asks `coach` with the moment, the dismissed nudges and the busy spans. The core picks one nudge and LAR says it.

**Reminders.** `scheduleReminders()` replaces every pending notification with the next week's from `reminders`. iOS keeps at most 64 pending, so the horizon is one week and each launch and sync renews it.

**Device calendar.** `refreshClassCalendar()` rewrites the IntPortal calendar through `plugin:calendar|sync_classes` when the classes, the marks or the day changed. `busyFrom()` reads the student's own events through `plugin:calendar|events`.

**Landing.** `landingAt(t)` returns the whole scene state for a time: pieces dropping, the swirl, LAR, the stones, the card. The components only draw it, which keeps the timeline unit-testable.

## On-device AI

IntAssis runs a small model through llama.cpp, on the phone, only after the student downloads one ([ADR 0003](adr/0003-on-device-ai-llama-cpp.md)). Two crates keep llama.cpp out of the core and out of Linux CI:

- `crates/intportal-ai` is pure Rust and depends on `intportal-core`. It holds the `Llm` trait, prompt budgets, run-time JSON schemas, reply parsing, RAG and batch generation, and is tested with a `FakeLlm`.
- `crates/intportal-llm` implements the trait with `llama-cpp-2` on iOS, Android and macOS, plus the model download and the memory gate. On Linux it is a stub that returns an error.

`src-tauri/src/ai.rs` runs inference in `spawn_blocking` and streams an open question's reply (and Ask AI results in a note) through a Tauri `Channel`. The chat model and the small embedding model sit in two slots and share one llama backend; `ai_ask` searches the student's notes with the embedder and shows the model what it found. The chat is kept in the encrypted store (`turns`). AI commands never write: the UI shows confirm cards, and Apply calls the existing commands (`set_note`, `save_deck`, `set_plan`, `set_mark`). Models live in `app_data_dir()/models/`, excluded from backup.

## Where to change things

| To change | Edit | Owner |
|---|---|---|
| What SIS pages are read, or how | `crates/intportal-core/src/sis/` | Core |
| A rule about classes, grades, study, reminders, the coach | the matching core module, test first | Core |
| A new command or its arguments | `src-tauri/src/lib.rs`, then `src/lib/api.ts` | Core, then UI |
| What a screen shows | `src/lib/screens/` and its components | UI |
| Shared app state or a flow across screens | `src/lib/state.svelte.ts` | UI |
| IntAssis prompts, schemas, RAG, model download | `crates/intportal-ai/`, `crates/intportal-llm/`, `src-tauri/src/ai.rs`, `src/lib/assis/` | AI |
| The widget, Live Activity, calendar on iOS | `plugins/*/ios/`, `src-tauri/gen/apple/` | Head |
| The same on Android | `plugins/*/android/`, `src-tauri/gen/android/` | Android |
| Info.plist keys, entitlements, deployment target | `src-tauri/gen/apple/project.yml` | Head |
| Build, run and size scripts | `scripts/` | QA/Release |
| CI | `.github/workflows/` | Head |

## Invariants

- **Data stays on the phone.** No backend and no sync between devices until the cloud tier ([ADR 0002](adr/0002-device-only-data.md)).
- **Only the student's own account.** That is what PUP's terms allow.
- **Logins are in the keychain**, one service per portal, never in the store, logs or localStorage.
- **No portal can get a student locked out.** Every sign-in goes through the guard: one POST per tap, at most three tries per 15 minutes per portal, no automatic retry after a rejection.
- **Portals don't share state.** A Mabini failure never fails an SIS sync, and the reverse.
- **Each student's store is SQLCipher-encrypted** with its own key in the keychain. A store that won't open is set aside, never deleted.
- **The core stays pure.** No platform APIs in `intportal-core`; anything that needs the phone goes in the shell or a plugin.
- **LAR speaks; Isko never does.** Copy follows `PRODUCT.md` and `DESIGN.md`.
- **Reduce Motion is honoured** everywhere, including the landing.
- **Anything that opens over the page registers its close with `closable()`**, so Android's back gesture closes it and not the app.

## iOS and Android

Both run the same Rust and the same Svelte. They differ only in the shell and the plugins:

| | iOS | Android |
|---|---|---|
| Keychain | Keychain Services (`keyring`) | Keystore-sealed values (`Secrets.kt`) |
| Store encryption | SQLCipher on CommonCrypto | SQLCipher on vendored OpenSSL |
| Next class outside the app | Live Activity, widget (widget needs a paid team for App Groups) | Live Update in the status bar, widget |
| Calendar | EventKit | CalendarContract |
| Native project | `gen/apple`, generated from `project.yml` | `gen/android`; see `docs/android.md` |

Desktop `cargo` builds compile neither the Swift nor the Kotlin. Only `scripts/sim.sh` and `scripts/emu.sh` prove them.

## Testing layers

| Layer | Tool | Where |
|---|---|---|
| Domain logic and parsers | `cargo test -p intportal-core` | `crates/intportal-core` |
| Pure TypeScript (timeline, layout, formatting) | vitest | `src/lib/*.test.ts` |
| Types across Svelte | `pnpm check` | `src/` |
| Shell compiles | `cargo test -p intportal`, clippy | `src-tauri` |
| Screens, native plugins | simulator and emulator screenshots | by hand, per PR |

## Decisions

- [0001](adr/0001-tauri-rust-svelte.md) Tauri, Rust and Svelte.
- [0002](adr/0002-device-only-data.md) Student data stays on the device.
- [0003](adr/0003-on-device-ai-llama-cpp.md) On-device AI runs llama.cpp in Rust; local only.
- [0004](adr/0004-landing-renders-in-rust-wasm-tiles.md) The landing renders in Rust/WASM tiles (planned).
- [0005](adr/0005-portals-are-first-class.md) Portals are first-class: SIS and Mabini (eMabini) are ready.

## Known debts

These feed the first sprint in `docs/TEAM.md`.

- `src-tauri/src/lib.rs` is about 1,070 lines and mixes commands, keychain, store opening and both portals' sign-in (#60).
- `src/lib/api.ts` types are hand-written copies of the Rust structs and can drift.
- Commands return strings for errors, so the UI can't tell offline, a failed sign-in and a locked store apart.
- The SIS parsers have no fixtures from real pages, so a change on PUP's side shows up only on a phone.
- `Today.svelte`, `Grades.svelte` and `You.svelte` are 450 to 650 lines each.
- Screens are checked only by hand on the simulator.

## Navigating the code

The repo is indexed with CodeGraph. Run `codegraph init -y` once per worktree (the index is gitignored), then `codegraph explore "<symbols or question>"` to get the source of the relevant symbols and the calls between them. It indexes Rust, TypeScript, Svelte, Swift and Kotlin.
