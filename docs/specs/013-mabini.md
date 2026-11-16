# 013 eMabini

**Status:** shipped (written after the fact for #131; eMabini shipped in #103 and #107)

## What changes for the student

A student who uses eMabini, PUP's Moodle at `emabini.pup.edu.ph`, adds its login once in the app. Their courses, deadlines and course grades sync to the phone, the deadlines join Today's Due list, and a Courses page lists each course with its progress. A student with only eMabini can use the app without the SIS.

## Direction and references

- The data map: [000](000-sis-data-map.md), the eMabini section.
- The portal model: [012](012-portals.md). eMabini is the second portal after the SIS, with its own theme (blue) and its own keychain entry.
- One deadline list: [041](041-one-deadline-list.md) C21 to C24.

## Keep

- The SIS sign-in, its guard and its store, untouched by anything eMabini does.

## Behaviour

- **C1.** You › Accounts adds an eMabini login (student number and password). The app fetches the login page, then makes one credential POST. Nothing else is sent.
- **C2.** The guard is the SIS's: 3 tries per 15 minutes, counted on the phone, and nothing tries again by itself after a rejected login (011 C11 to C16, 050 C1 to C5). Its count is its own file, `mabini-guard.json`.
- **C3.** The login is kept in the keychain under its own service, `ph.intportal.app.mabini`, never the SIS's.
- **C4.** A sync reads the courses, the upcoming deadlines and the course grades. A part that fails keeps the last good copy of that part, and only an expired session fails the whole sync.
- **C5.** eMabini's deadlines show in Today's Due list, in reminders, in LAR's nudges and in the calendar, as 041 says. Opening one opens it on eMabini, and only on PUP's https hosts (050 C6).
- **C6.** The Courses page lists each course with its section, term and progress, and opens it on eMabini.
- **C7.** A student signed in to eMabini alone uses the app without the SIS. LAR wears eMabini's colours.
- **C8.** A rejected saved login shows "eMabini turned your login down. Changed your password?" with the form filled in, so it can be edited without signing out.
- **C9.** Signing out of eMabini removes its login and its data, and keeps the SIS's.
- **C10.** An eMabini login must belong to the student signed in to the SIS on the phone, if any. Another student's is refused.

## Data shape

- `crates/intportal-core/src/mabini/`: `LoginPage`, `MabiniClient`, `MabiniData { courses, deadlines, grades, last_synced }`.
- The data is one `mabini` row in the student's own encrypted store, not a store of its own. This is the one way the build differs from 012 C4, which asked for a separate namespace. It is kept: the row lives and dies with the student's store, and C9 removes it.

## Errors

The copy is in `src/lib/errors.ts` and the portal's own `rejected_again` (050 C5).

## Test map

| Criterion | Check |
|---|---|
| C1, C2 | `cargo test -p intportal-core guard` (`post_once`, `c5_the_refusal_names_the_portal`) |
| C4 | `cargo test -p intportal-core mabini` |
| C5 | `cargo test -p intportal-core deadline` |
| C10 | `cargo test -p intportal c128_1_mabini_attaches_only_to_the_signed_in_student` |
| C3, C6 to C9 | the simulator, and the owner's phone |
