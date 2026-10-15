# 011 Login

**Status:** draft

## What changes for the student

The sign-in form gets proper controls: spinning wheels for the birthdate, a masked student-number field, a show-password toggle, and a visible count of tries left. Behind it, a guard makes sure IntPortal can never lock a student out of their SIS account by sending too many logins.

## Direction and references

Typography is a new pair from OFL fonts: Geist for the interface and Pixelify Sans for the wordmark, as tried in [portal-v8.html](reference/prototypes/portal-v8.html). Licences are checked in `DESIGN.md`. The form sits below the portal ([010](010-landing.md) C16) and under LAR's line. The SIS fields are in the data map ([000](000-sis-data-map.md)).

## Keep

- The three inputs: student number, birthdate, password.
- Campus detection from the student number, with its "campus found" and "not confirmed yet, sign-in still works" lines.
- The demo link in review builds (`__REVIEW__`).
- Step through for returning students.
- The keychain note: "Your login stays in this phone's keychain. IntPortal only talks to PUP SIS."
- Nobody but the student types or stores the SIS password.

## Behaviour

**Form**

- **C1.** The birthdate is three wheels (month, day, year) with stepped snapping and one haptic tick per step.
- **C2.** The year wheel offers a plausible range (the current year minus 14 down to minus 70).
- **C3.** The day wheel never offers a day the chosen month and year do not have.
- **C4.** The student number is masked as `YYYY-NNNNN-CC-N` while typing. Pasting an unmasked number formats it.
- **C5.** The password field has a show/hide toggle; it defaults to hidden and returns to hidden when the app backgrounds.
- **C6.** A line under the form says `N tries left` once the student has used any attempt in the current window.
- **C7.** Sign in is disabled until all fields are valid and while a request is running.

**States**

- **C8.** A rejected login shows the SIS's own message, or the fallback "Sign-in didn't go through. Check your student number, birthdate and password."
- **C9.** When no SIS host answers, the form shows an "SIS is down" state with a Try again button. This is not counted as a rejected login.
- **C10.** A signed-in account whose schedule is empty on every probed host shows "Signed in, but your schedule isn't up yet" and still lets the student in.

**Lockout guard** (core; the UI only shows its result)

- **C11.** One credential POST per tap of Sign in.
- **C12.** At most 3 login attempts per 15 minutes per portal, counted on the phone and persisted across restarts.
- **C13.** A plain GET picks a live host before any credential is sent. A host that does not answer the probe is never sent a credential.
- **C14.** Failover to another host happens only on connection errors that occur before the credential POST.
- **C15.** A signed-in result with no schedule is reused, not retried on other hosts. Any further host check uses the open session, never a new sign-in.
- **C16.** After a rejected password, nothing signs in again automatically (sync, launch, the minute ticker) until the student edits the login.
- **C17.** When the limit is reached the form is disabled and shows when sign-in unlocks, for example "Too many tries. You can try again at 3:42 PM."

## Copy

| Where | Text |
|---|---|
| Student number placeholder | `2026-00000-MN-0` |
| Birthdate label | `Birthdate` |
| Password label | `Password` |
| Toggle | `Show` / `Hide` |
| Tries line | `2 tries left` (singular `1 try left`) |
| Button | `Sign in` / `Signing in…` |
| Rejected fallback | `Sign-in didn't go through. Check your student number, birthdate and password.` |
| Down | `SIS is down right now. Your data is safe. Try again in a bit.` |
| Locked | `Too many tries. You can try again at 3:42 PM.` |
| Keychain note | `Your login stays in this phone's keychain. IntPortal only talks to PUP SIS.` |

Mabini variants (shipped): the card has student number and password only; LAR says "Hi, I'm LAR. Sign in to eMabini and I'll bring your courses and deadlines."; the keychain note ends "IntPortal only talks to PUP eMabini."; the button reads `Sign in` on the landing and `Sign in to Mabini` inside You. Its tries line is counted apart from the SIS's.

LAR's lines follow the stage ([010](010-landing.md) C19).

## Data shape

- `Credentials` and `Error` in `crates/intportal-core/src/sis/mod.rs` stay. New: an attempt ledger per portal `{ portal_id, attempts: [timestamp] }`, persisted outside the encrypted student store (a student with no account yet still has attempts).
- The core exposes `tries_left(portal) -> { left, window_ends_at }` to the UI through the typed IPC (issue #61).
- `sign_in_with_failover` in `sis/client.rs` and `host::decide` in `sis/host.rs` are reworked to follow C11–C15: probe first, one POST, no host loop after a signed-in result.
- The `sync` command in `src-tauri/src/lib.rs` signs in again from the vault on expiry; it must obey C12 and C16.

## Errors

| Failure | Student sees | Counted? |
|---|---|---|
| SIS rejects the password | SIS message (C8) | yes |
| No host answers the probe | "SIS is down" (C9) | no |
| Network drops before the POST | "SIS is down" (C9) | no |
| Network drops after the POST | the same, plus "check your connection"; the guard assumes the POST was spent | yes |
| Signed in, schedule empty | enter with a note (C10) | no |
| Limit reached | Locked line (C17) | n/a |

## Motion and Reduce Motion

- Wheels snap with a stepped motion and a haptic tick; under Reduce Motion they snap without animation and keep the tick off.
- The portal does not move while a field has focus ([010](010-landing.md) C17).

## Accessibility

- Wheels are adjustable controls (swipe up/down) with a text value read out; a typed fallback exists for VoiceOver and TalkBack.
- The tries and error lines are `aria-live`.
- Inputs are 46 px tall or more and keep the 16 px minimum font.
- Dynamic Type follows the existing capped-growth rule in `DESIGN.md`.

## Out of scope

- Biometric unlock (the lock screen already exists).
- Signing in to Mabini.
- Changing the keychain scheme.

## Test map

| Criterion | Check |
|---|---|
| C1–C5 | vitest on the wheel and mask logic; screenshots |
| C6, C17 | vitest on the tries view; screenshot |
| C7–C10 | screenshot with a fake core |
| C11–C15 | `cargo test -p intportal-core` in `sis/` with a fake client: counts POSTs per scenario |
| C12 | `cargo test`: three rejects within 15 minutes block the fourth; the window slides |
| C16 | `cargo test -p intportal`: `sync` after a reject performs zero POSTs |

## Open questions

- Is the 3-per-15-minutes limit also right for a *successful* sign-in that follows a rejected one?
- Should a reset clear the ledger if the student edits the login (proposed: no, edits don't reset the window).
