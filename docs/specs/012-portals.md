# 012 Portals

**Status:** draft

## What changes for the student

IntPortal stops being "the SIS app" and becomes a door to several PUP systems. Today there is one portal, the SIS. Mabini, PUP's learning system, is listed and shows "Opens soon". Each portal has its own login, its own limits and its own look.

## Direction and references

The landing already speaks of a portal as the gate to a system ([010](010-landing.md)). This spec makes that real in the core: a portal is a first-class thing with a name, a status and a theme. See [ADR 0005](../adr/0005-portals-are-first-class.md) and the data map ([000](000-sis-data-map.md)).

## Keep

- SIS sign-in, sync and storage behave exactly as today.
- One encrypted store per student number.
- The login stays in the platform keychain.
- Own-account-only scope.

## Behaviour

- **C1.** A `Portal` has: `id`, `name`, `status` (`ready` or `opens_soon`), `theme`, `sign_in` fields, attempt limits, and a keychain service name.
- **C2.** SIS is the only `ready` portal. Mabini (eMabini, the Open University's Moodle portal) is listed as `opens_soon`. Its sign-in fields are student number and password, with no birthdate; its username is the student number lowercased with dashes removed.
- **C3.** An `opens_soon` portal cannot be signed in to or stepped into. The UI shows "Opens soon" and offers no form.
- **C4.** Each portal has its own connection state and its own store namespace. Signing in to or syncing one portal never reads or writes another's data.
- **C5.** Each portal has its own keychain entry. Clearing one never clears another.
- **C6.** Each portal has its own attempt counter ([011](011-login.md) C12). A rejected SIS login does not spend Mabini attempts.
- **C7.** A portal's `theme` is five ramp tones plus one accent. SIS is PUP maroon and gold. Mabini's brand colour is the same maroon (`#700000`), so its ramp keeps that maroon and takes a teal accent (`#5fd0d6`) to tell the two apart. The user approves the palette.
- **C8.** The registry lists portals in a fixed order; the landing carousel follows it ([010](010-landing.md) C13).
- **C9.** Migrating SIS onto the registry changes no behaviour: existing stores, keychain entries and snapshots keep working untouched.
- **C10.** Adding a portal is one registry entry plus its client; no landing or login code branches on a portal id.

## Copy

- Status label for an unready portal: `Opens soon`.
- Portal names: `SIS` (PUP Student Information System) and `Mabini`.
- The word "portal" in copy means one PUP system, never the website ([CONTEXT.md](../../CONTEXT.md)).

## Data shape

New in the core, `crates/intportal-core/src/portal.rs` (name provisional):

```rust
pub struct Portal {
    pub id: &'static str,          // "sis", "mabini"
    pub name: &'static str,
    pub status: Status,            // Ready | OpensSoon
    pub theme: Theme,              // 5-tone ramp + accent
    pub fields: &'static [Field],  // sign-in fields, in order
    pub limits: Limits,            // attempts per window
    pub keychain_service: &'static str,
}
```

Shipped in [intportal-app#97](https://github.com/cGradying/intportal-app/pull/97): `portal.rs` with `SIS`, `MABINI` and `get(id)`.

The SIS client in `crates/intportal-core/src/sis/` becomes the SIS portal's implementation. Store namespacing extends `account_file` in `store.rs` so a portal id is part of the file key.

## Errors

- Choosing an `opens_soon` portal: no error; the card says "Opens soon".
- A portal whose host is down: that portal's "down" state ([011](011-login.md) C9), others unaffected.

## Motion and Reduce Motion

The carousel's motion is specified in [010](010-landing.md). The registry itself has none.

## Accessibility

Each portal in the carousel is a labelled button: "SIS, ready" or "Mabini, opens soon, unavailable".

## Out of scope

- Mabini's pages, fields and sync (waiting on captures).
- Cross-portal features such as one combined Today.
- Cloud accounts ([ADR 0002](../adr/0002-device-only-data.md)).

## Test map

| Criterion | Check |
|---|---|
| C1–C3, C8 | `cargo test -p intportal-core portal::` |
| C4–C6, C9 | `cargo test -p intportal-core` with two fake portals and a temp store |
| C7 | `cargo test`: every theme has five tones and an accent |
| C10 | review: grep for portal-id branches in `src/` |

## Open questions

- Approve Mabini's palette (maroon ramp, teal accent).
- Confirm with a real eMabini account that the username format and the sign-in form match [000](000-sis-data-map.md).
