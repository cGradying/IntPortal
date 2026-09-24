# 00 — SIS host failover

## Problem

PUP SIS runs on several numbered hosts (`sisN.pup.edu.ph`). The user sees the right one change
between sis1 and sis8, and doesn't know if there are more.

What the app does today (`Sources/PUPSISPortalApp/Core/PortalController.swift`):

- `defaultBase` is `https://sis8.pup.edu.ph/student` (line 57). `base` reads the last host from
  `UserDefaults` key `sisBaseHost`, falling back to sis8.
- `adoptActualHost()` (line 88) runs after sign-in and follows the post-login redirect to
  whichever host the web view landed on, trusting only https `*.pup.edu.ph`.
- `currentHost` is shown in Settings › Technical Details.
- `windows/PUPSISPortal.Core/SisSession.cs:38` hard-codes sis8.

What's missing: a single host is tried. If it's down, sign-in times out. If it's up but not
carrying this student's data, sign-in "works" and the schedule scrapes empty.

## Evidence

- Commit `f763487` (2026-09-04): sis1 logs in and stays on its own dashboard but never carries the
  student's schedule; sis8 is the host that serves it. **Mirrors are not interchangeable**, so a
  host passing the login page proves nothing.
- Probe on 2026-09-23, GET `https://sisN.pup.edu.ph/student/`, N = 1…10:

| Host | Result |
|---|---|
| sis1, sis2, sis8 | 200, no redirect, title "PUPSIS - Student Module (Beta)", contains `id="studno"`, form posts to its own host |
| sis3–7, sis9, sis10 | no response |

## Behaviour

1. **Candidates.** Remembered host first, then `[sis8, sis1, sis2]` without duplicates.
2. **Reachability pre-check.** Before sign-in, GET each candidate's `/student/` in parallel, short
   timeout (about 6 s). Drop hosts that don't answer 200 with `id="studno"` in the body. No
   credentials or cookies are sent.
3. **Sign in** on the first reachable candidate using the existing flow unchanged
   (`fillAndSubmitScript`, `awaitSignInOutcome`, `adoptActualHost`).
4. **Data check.** A host counts as good only when sign-in succeeds **and** the schedule page
   scrapes at least one row. Validation modal (wrong password) stops immediately: never retry
   bad credentials on other hosts.
5. **Failover.** Timeout, network error, or signed-in-but-empty-schedule moves to the next
   reachable candidate. Only a good host is written to `sisBaseHost`.
6. **All empty.** If every reachable host signs in but none has schedule rows, treat it as a real
   empty term: keep the remembered host, keep the cached schedule (existing guard in
   `loadSchedule`), show the existing "No classes found" message.
7. **None reachable.** Existing error, naming the hosts tried.
8. **Mid-session.** A refresh that times out re-runs steps 2–5 once.
9. **Override.** Settings › Account: "SIS server", Automatic (default) or a fixed host. A fixed host
   skips pre-check and failover.

## UI

- Settings › Technical Details keeps showing `currentHost`.
- Settings › Account gains the "SIS server" row.
- Login screen: when failover picked a host other than the remembered one, one quiet line, e.g.
  "Using sis8, sis1 had no schedule for you."

## Acceptance criteria

- [ ] Pure candidate-ordering and reachability function tested with fixtures: login page passes,
      200 error page fails, timeout fails, remembered host goes first. Evidence: XCTest name.
- [ ] Failover decision tested as a pure function over outcomes (reachable / signed-in /
      rows > 0 / validation error). Wrong password never tries a second host. Evidence: XCTest name.
- [ ] Only a host with schedule rows is persisted to `sisBaseHost`. Evidence: test.
- [ ] With the remembered host blocked in `/etc/hosts`, sign-in lands on another host and the
      login line names it. Evidence: screenshot.
- [ ] Fixed-host override skips probing. Evidence: manual step.
- [ ] `swift test` passes.
- [ ] `pupsis-security` review: credentials only ever go to https `*.pup.edu.ph`, never to a host
      after a validation error, probing sends none.

## Seams

- `PortalController`: sign-in flow wraps the existing steps in a candidate loop. Public API
  (`signIn(with:)`, `loadSchedule()`, `loadGrades()`, `currentHost`) unchanged.
- `UserDefaults` `sisBaseHost` stays the storage; one new key for the override.
- `SettingsView` Account pane, `CredentialsView`: one row, one line.

## Out of scope

- Windows `SisSession.cs` (port benched). Same logic applies when it restarts.
- Hosts beyond `sis1…sis10`.
- Picking the fastest host.

## Open question

- Does the redirect after sign-in on sis1 ever move a session to sis8 by itself? If
  `adoptActualHost()` already catches that, the data check only matters when it doesn't. Confirm
  on the live site before building.
