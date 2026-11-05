# 047 You and themes

**Status:** draft for review. Every look is picked (round two, 2026-11-05, on the [study picks page](reference/prototypes/study-you.src.html)). The user merges after the Head's review.

## What changes for the student

You fits on one screen: short rows that open their own pages, with search across every setting. There are new settings for layout, motion and backup. Students can make their own theme and hand it to a classmate by code or QR.

## Direction and references

- User's answers, 2026-11-05: clean and compact; the big eMabini card goes but eMabini stays; code and QR; add layout, motion and backup settings.
- Colour: `derive` and its contrast clamps in `src/lib/rooms.ts`.
- The Roles Not Hex Rule and the School's Colours Rule in `DESIGN.md`.

## Keep

Every setting on You today, reachable within two taps:
- SIS: last synced, server, Sync now, a rejected login's form, sign out.
- eMabini: last synced, its errors, Sync now, Courses, a rejected login's form, sign out.
- IntAssis `ModelCard`.
- Reminders: class lead, deadlines, study, warm-up, note after class, Sunday brief, the notifications prompt, the next-reminder line.
- Rooms, text style (Classic), haptics, sounds.
- Calendar: keep classes, own events, last day, Add classes to calendar.
- Privacy: lock, the privacy lines, sign out, Erase everything with its confirm.
- Isko and LAR in the header, the about line, the review builds' design gallery.

## Behaviour

**One screen**
- **C1.** You's home is a list of rows: Accounts, Theme, Reminders, Calendar, Layout, Motion and effects, IntAssis, Backup and data, Privacy. Each shows its current value and opens a page. Rows are grouped: Account, Look, Alerts, Data. Eight switches (haptics, sounds, lock, moving ground, class, deadline and study nudges, calendar) and search are pinned above the tab bar, in thumb reach. A lit switch shows gold on its icon and edge, not a gold block. Each page closes with a large Back at the bottom. Every target is at least 48 pt.
- **C2.** Search matches every setting's name and synonyms, in English and common Taglish words, and goes to its page.
- **C3.** A problem shows on its row: a rejected login on Accounts, notifications off on Reminders. It never hides a page deep.
- **C4.** Accounts holds SIS and eMabini as two compact blocks. eMabini's sync and Due feed don't change, and it can still be connected or signed out here.

**New settings**
- **C5.** App opens on: Today, Schedule or Study. The dive still lands on the chosen tab.
- **C6.** Today's cards: show or hide and reorder Up next, Due, LAR's plan, This term and Your events. Up next and Due can't both be hidden, for "never miss a deadline". *Reorder is buttons, no drag, so it works with VoiceOver.*
- **C7.** Lists: Comfy or Compact. Compact keeps every target at least 44 pt.
- **C8.** The dive: Full, Short or Off. Done effects: Full, Calm or Off. Moving ground: on or off. The phone's Reduce Motion wins over all of them.
- **C9.** Backup: one file with notes (with subject and pin), photos, decks, syllabus pages, goals, marks and themes. Logins are never in it. It's built from the data, never a copy of the store: a restored store can't open without this phone's keychain key, and Android has `allowBackup=false`, so this file is the only way to a new phone.
- **C10.** Restore shows what's in the file and asks before it replaces anything. A file from a newer app version, or a damaged one, is refused and changes nothing.
- **C11.** Backup and data shows the space notes, photos, decks and the rest take. The AI model's size stays on its card.

**Custom themes**
- **C12.** Make a theme: a live preview on top with Today, Study and Dive tabs, and every control in the bottom half, with section tabs at the very bottom: Colour, Ground, Shape, LAR, Share.
  - **Colour:** presets, an accent and a night-to-day slider that set the whole theme, optional fine tuning.
  - **Ground:** ten patterns (dots, squares, bold, plus, hearts, stars, checks, lines, grid, none), pool colour, moving pools full, soft or still.
  - **Shape:** corners (stepped, deep, round, sharp), cards (filled, outline, tinted), titles (phone, classic, pixel).
  - **LAR:** his colour, or the school's. The Dive preview shows the tunnel in this theme.
  - **Share:** name, share card, save, scan.
  - **The dice** on the preview rolls a whole theme and a name.
- **C13.** Every theme goes through the clamps when applied: text at least 7:1 on cards, quieter text 4.5:1, the accent 3:1. The student's picks can't make it unreadable.
- **C14.** Saved themes sit beside the rooms and can be renamed or deleted. Deleting the active one falls back to Night.
- **C15.** A theme applies to the whole app, including derived subject colours and the ground. The landing and the portal keep their own world.

**Sharing**
- **C16.** Share gives a code and a QR of it. Format `IPT1.` plus base64url of: version, choices (pattern, moving pools, corners, cards, titles), two hues, four RGB colours, name length, name (at most 24 characters), and a checksum byte. The code sits on a theme card with the QR, in the theme's own colours.
- **C17.** A code holds colours and a name only. Decoding validates length, version and checksum, and the name is shown as plain text and never as markup.
- **C18.** Add a theme by pasting a code or photographing its QR. The student sees it first and chooses Keep or Not now. A bad code changes nothing and says so.
- **C19.** Sharing needs no network and no account. Nothing about the student is in the code.

## Copy

As on the picks page. Final strings go here after the picks.

## Data shape

- Themes: `{ name, accent, ground, card, ink, hue2, lar, pattern, aura, corners, cards, titles }`, stored with settings and included in backups. They survive sign-out, and Erase everything removes them.
- `src/lib/rooms.ts`: `derive` gains a path from a theme; `applyRoom` accepts a saved theme's id. `themeCode.ts`: `encodeTheme`, `decodeTheme`.
- QR drawing: `qrcode-generator` (new dependency, small, MIT; licence to check before it ships).
- QR scanning: the one camera plugin, shared with Scan (#197) and 046's photos, owned by the Head. `plugin:camera|capture` with `{ source: "camera", read: { qr: true } }` takes one photo and keeps nothing; there's no live scanner. Until it lands, paste works alone. If the user chooses Play services for Android's reader, the first QR read needs a one-time download, so 047 adds an offline line then.
- Backup commands: `src-tauri/src/lib.rs` is a hot file, so they go in one small PR.

## Errors

- Bad code: "That code doesn't look right, so nothing changed. Ask for it again."
- No camera permission: a line on how to allow it, with paste offered.
- Backup can't be written or read: says which, and changes nothing.

## Motion and Reduce Motion

Pages slide in over 0.26 s with the shared ease. Quick switches press one step. `SAVED` stamps with `steps()`. Reduce Motion skips to rest. Haptics: `select` on a segment, `tick` on a switch, `done` on Save and Keep.

## Accessibility

Rows and switches are 44 pt, with names and states read out. Colour sliders have values read out and are never the only way to set a colour: fine tuning takes a colour picker. Contrast clamps cover the rest.

## Test map

| Criterion | Test |
|---|---|
| C2 | `vitest`: `c2_search_finds_every_setting` |
| C5–C8 | `vitest`: settings round trip, `c6_due_and_next_not_both_hidden` |
| C9, C10 | `cargo`: `c9_backup_has_no_logins`, `c10_bad_backup_changes_nothing` |
| C13 | `vitest`: `c13_every_theme_meets_contrast` over a sweep of colours |
| C16, C17 | `vitest`: `c16_code_round_trip`, `c17_bad_code_refused` (cut, tampered, wrong version, markup in the name) |
| C1, C3, C4, C12, C18 | screenshot, real phone |

## Open questions

- Notes on You (046 C8): the recommendation is a short row that opens them. It stays as today until the user answers.
- Backup: the store is encrypted but this file would not be. Keep it plain with a clear warning, or add a password flow? It holds private notes, and the student decides where it goes.
