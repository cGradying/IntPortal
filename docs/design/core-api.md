# Core API: the boundary between the Rust core and the Svelte UI

The UI never parses, computes a GPA or talks to the SIS. It calls Tauri commands in `src-tauri/src/lib.rs`, which are thin wrappers over `intportal-core`.

## Data the UI holds

- **`Snapshot`** (`core::store`) is everything on the device: sessions, current grades, grade history, marks, subject colours, the remembered host, and `last_synced` (UNIX seconds). The UI keeps one copy in a Svelte store and replaces it with whatever a command returns.
- **`Today`** is computed on request from a `Moment`, which is the device's local date (`"2026-08-03"`) and the minute of the day. The core has no clock and no time zones. The UI asks again every minute.

## Commands

| Command | Returns | Notes |
| --- | --- | --- |
| `snapshot()` | `Snapshot` | Instant, from SQLite. The first frame reads this. |
| `has_login()` | `bool` | Whether the keychain holds a login. It decides the hub or sign-in. |
| `sign_in(login)` | `Snapshot` | Host failover, then the login is saved to the keychain only after success. |
| `sync()` | `Snapshot` | A background refresh. It signs in again from the keychain when the session expired. |
| `load_history()` | `Snapshot` | Walks every past term. Slow, so it runs only when asked. |
| `set_mark(session_id, week?, mark?)` | `Snapshot` | `week` scopes the mark to one week; `mark: null` clears it. |
| `today(now, sync_trouble?)` | `Today` | Agenda, next class, countdown text, and the glance and its line. |
| `sign_out()` | `()` | Wipes the store and the keychain, and drops the session. |
| `demo(today)` | `Snapshot` | Debug builds only: a fake week and term for review. |

## Errors

Commands return `Result<_, String>`, and the string is written for the student ("Sign-in didn't go through. Check your student number, birthdate and password."). A failed `sync` never clears the snapshot. The UI keeps showing the cached week and puts the message in the glance (the sync-trouble case).

## Not yet

- Push-style sync progress events. Add them when the jeepney sync moment needs a progress beat, not before.
- Android credential storage (#15).
