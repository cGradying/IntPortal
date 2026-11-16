# 050 Release 0.4: finish the app

**Status:** shipped. C1 to C19 are on main; C4, C7 and C8 were already true.

## What changes for the student

The app they install from the new website is the finished one: a sign-in guard that can't be fooled into locking them out, a deck that says how well they know it and what is due this week, the current week marked in a syllabus, and eMabini links that only open where they should. The "Updates" link in You opens the website.

## Direction and references

The open issues that are still wanted for a public release: #129, #130, #131, #241, #267, #269 (first half), #69. Everything else open is either shipped, blocked on a paid Apple account, or a later feature, and is closed or relabelled with a note.

## Keep

- Every shipped spec's behaviour. Nothing on screen is removed.
- The guard's numbers: 3 tries per 15 minutes per portal, and no automatic retry after a rejected login (011 C11 to C16).
- No network call that isn't to a PUP host or the opt-in model download (ADR 0002, PRIVACY.md).

## Behaviour

### The guard (#129)

- **C1.** The guard reads its numbers from the portal (`portal::Portal.limits`). The constants in `sis/guard.rs` are gone.
- **C2.** A ledger file that can't be read or parsed counts as "no tries left" until a full window passes from the moment it was found broken. It never counts as a fresh ledger.
- **C3.** The ledger is written atomically (a temporary file, then a rename). A failed write is returned as an error, not dropped.
- **C4.** The rejected mark clears only through the sign-in form, which never refills the password, so a cleared mark always means a retyped login. Sync, launch and the minute ticker never clear it. *Already true on main; nothing changed.*
- **C5.** The rejection text comes from the portal: SIS mentions the birthdate, eMabini does not.

### eMabini (#130)

- **C6.** A link from portal data (a course, a deadline) opens only if it is https and on `emabini.pup.edu.ph` or a SIS host. A link the student typed keeps the https-only rule.
- **C7.** A rejected eMabini login can be edited from You, without signing out first. *Already true on main (You › Accounts shows the prefilled eMabini form).*
- **C8.** Test data uses the placeholder student number pattern `2024-00000-MN-0`. *Already true on main.*

### Study (#267)

- **C9.** A deck's mastery is the share of its cards with at least 2 reviews and a stability of at least 7 days. A new deck reads 0%.
- **C10.** A deck's 7-day forecast counts the cards due on each of the next 7 local days; overdue cards count toward today.
- **C11.** The deck row in Decks shows mastery as a percentage under the deck's name and the forecast as seven small pixel bars beside the due count. Nothing there is removed.

### Syllabus (#269, first half)

- **C12.** In a subject's syllabus, the rows dated in the current Monday-to-Sunday week sit on the Gold Wash (`--gold-soft`) with a gold "This week" label. Rows with only a week number aren't marked: the app doesn't know the term's first day.

### The due adder (#241)

- **C13.** The subject guess (letters like COMP pick the subject that meets on the draft's day) runs in the core's `parse_own`, so every caller gets it. The TypeScript copy is deleted.
- **C14.** A student's fixes to a pasted multi-line message are keyed by line, so editing one line can't move a fix onto another ticket.

### Release (#69, #131)

- **C15.** "Updates" in You opens the website's download page (the site's address lives in one constant). Until the site is live it opens the GitHub releases page.
- **C16.** Each release carries a version-less `IntPortal.apk` next to `IntPortal-<version>.apk`, so `releases/latest/download/IntPortal.apk` always gets the newest.
- **C17.** An unsigned iPhone app (`IntPortal-<version>-unsigned.ipa`) is built by `scripts/ipa.sh`, locally or by running the iOS workflow by hand, for sideloading with AltStore or SideStore.
- **C18.** `docs/RELEASING.md` holds the release checklist: checks, version, changelog, the signed Android build, the IPA, the draft, the owner's "publish".
- **C19.** `docs/specs/013-mabini.md` says what eMabini does on main, and 000, 020 and 030 carry an honest status, criterion by criterion.

## Copy

- Deck row: `{n}% known` and, for screen readers, `Due this week: {d0} today, {d1} tomorrow, …`.
- Syllabus: the gold mark has the accessible label `This week`.
- eMabini rejection: "eMabini turned your login down. Update your username or password to try again."
- SIS rejection: unchanged.

## Data shape

- `crates/intportal-core/src/study.rs`: `mastery(cards: &[Card]) -> f64`, `forecast_7(cards: &[Card], today: Date) -> [u32; 7]`. `StudyOverview`'s deck entries gain `mastery` and `forecast`.
- `crates/intportal-core/src/sis/guard.rs`: `Ledger` gains `broken_at: Option<u64>`.
- `crates/intportal-core/src/deadline.rs` (`parse_own`): drafts gain `subject: Option<String>`.

## Errors

- A broken ledger: the sign-in button says when the next try frees up, as for a used-up ledger.
- A ledger that can't be written: "Couldn't save the sign-in count. Try again in a moment." and no POST is sent.

## Motion and Reduce Motion

No new motion. The forecast bars don't animate.

## Accessibility

The forecast is read out as one sentence (Copy). Mastery is text, not colour alone.

## Out of scope

- Quiz me on a lecture row (#269, second half): it waits for spec 022.
- AI features #80 to #82, #141, #142: they stay open for after 0.4.
- Typed bindings and splitting the big screens (#61 to #65): refactors with no change for the student.

## Test map

| Criterion | Check |
|---|---|
| C1 to C5 | `cargo test -p intportal-core guard` (`c1_`, `c2_`, `c3_`, `c5_`) |
| C6 | `vitest openLink` |
| C7, C8 | already on main |
| C9, C10 | `cargo test -p intportal-core study::mastery`, `study::forecast` |
| C11, C12 | `vitest shelf`, `vitest thisWeek`, screenshot |
| C13, C14 | `cargo test -p intportal-core c13_guess_subject_from_letters`, `vitest addDue` |
| C15 | `vitest links` |
| C16, C17 | `scripts/release.sh` and `scripts/ipa.sh` (the IPA was built and packaged on this Mac: 7.3 MB, unsigned); the iOS workflow's manual run |
| C18, C19 | review |

## Open questions

None.
