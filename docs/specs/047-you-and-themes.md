# 047 You and themes

**Status:** approved (2026-11-05). The user took the recommendations: the dive keeps Off, and backup has no password, with a clear warning.

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
- LAR in the header (the Isko mascot was retired 2026-11-09: the student is Isko), the about line, the review builds' design gallery.

## Behaviour

**One screen**
- **C1.** You's home is a list of rows: Accounts, Theme, Reminders, Calendar, Layout, Motion and effects, IntAssis, Backup and data, Privacy. Each shows its current value and opens a page. Rows are grouped: Account, Look, Alerts, Data. Eight switches (haptics, sounds, lock, moving ground, class, deadline and study nudges, calendar) and search stay at the top of the screen, above the rows (the user, 2026-11-05; the picks page still shows them at the bottom). A lit switch shows gold on its icon and edge, not a gold block. Each page closes with a large Back at the bottom. Every target is at least 48 pt, or 44 pt in Compact (C7).
  *Built 2026-11-09:* rows also include Notes (in Data), the student's pick of notes on You as a short row; it opens the notes card. The quick switches and search are at the top. Classes, Deadlines and Study switch back on at the time they had before they were turned off. Back is the last thing on each page, in the page's flow rather than pinned.
- **C2.** Search matches every setting's name and synonyms, in English and common Taglish words, and goes to its page.
  *Built 2026-11-09:* `searchSettings` in `src/lib/you.ts` matches 30 settings; every word typed must appear in a setting's name or words, ignoring case and accents. Results show the setting with its page.
- **C3.** A problem shows on its row: a rejected login on Accounts, notifications off on Reminders. It never hides a page deep.
  *Built 2026-11-09:* also eMabini's sync error on Accounts, a reminder that couldn't be scheduled on Reminders, and a lock that couldn't turn on on Privacy. Notifications off only counts while any nudge is on.
- **C4.** Accounts holds SIS and eMabini as two compact blocks. eMabini's sync and Due feed don't change, and it can still be connected or signed out here.
  *Built 2026-11-09:* sign-out of SIS (with its confirm) and of eMabini moved here from Privacy, which keeps Erase everything and points to Accounts for signing out.

**New settings**
- **C5.** App opens on: Today, Schedule or Study. The dive still lands on the chosen tab.
  *Built 2026-11-09:* stored on the phone (`opensOn`); Android's back still goes to Today.
- **C6.** Today's cards: show or hide and reorder Up next, Due, LAR's plan, This term and Your events. A student can hide Due (the user's call, 2026-11-05, against the Head's recommendation). Hiding it only removes the card: reminders and nudges keep working. *Reorder is buttons, no drag, so it works with VoiceOver.*
  *Built 2026-11-09:* Your events are rows inside Today's list, not a card, so they hide but don't move; hiding them keeps their time counted in the free stretches and LAR's plan. The four cards move with up and down buttons. Stored as `todayCards`.
- **C7.** Lists: Comfy or Compact. Compact keeps every target at least 44 pt.
  *Built 2026-11-09:* Compact shortens You's rows and switches and Today's class rows, all still at least 44 pt.
- **C8.** The dive: Full, Short or Off. Off reverses the 10-25 decision that dropped the "Play portal on open" switch (the user, 2026-11-05). With Off, the 040 C2 skeleton shows while data loads. Done effects: Full, Calm or Off. Moving ground: on or off. The phone's Reduce Motion wins over all of them.
  *Built 2026-11-09:* Short runs the same dive at double speed. Off also skips the dive after Step through. Calm is a third of the sparks and 24 confetti bits instead of 70. Moving ground off stops the pools where they are.
- **C9.** Backup: one file with notes (with subject and pin), photos, decks, syllabus pages, goals, marks, own deadlines and Done marks (`own_deadlines`, `done`, spec 041), subject colours, the study streak (`study_stats`), `class_info` once 030 C1 lands, and themes. Sign-out keeps all of this, so a new phone gets it too. Logins are never in it. The file is not encrypted, has no password, and says so plainly before it's saved (the user, 2026-11-05). It's built from the data, never a copy of the store: a restored store can't open without this phone's keychain key, and Android has `allowBackup=false`, so this file is the only way to a new phone.
  *Built 2026-11-09:* not yet. The core has no backup command, so the page says "Coming in the next update", describes the file, the missing password and what's never in it, and offers Notes' Export all meanwhile.
- **C10.** Restore shows what's in the file and asks before it replaces anything. A file from a newer app version, or a damaged one, is refused and changes nothing. The file carries a hash of the student's number, and each student has their own store, so a file from another student is refused the same way. Restore needs someone signed in, because the check has nothing to compare against otherwise: on a new phone it says "Sign in first, then restore", and changes nothing.
  *Built 2026-11-09:* not yet; needs the core restore command with the student-number hash check.
- **C11.** Backup and data shows the space notes, photos, decks and the rest take. The AI model's size stays on its card.
  *Built 2026-11-09:* not yet; needs a core command for sizes. The row says Coming.

**Custom themes**
- **C12.** Make a theme: a live preview on top with Today, Study and Dive tabs, and every control in the bottom half, with section tabs at the very bottom: Colour, Ground, Shape, LAR, Share.
  - **Colour:** presets, an accent and a night-to-day slider that set the whole theme, optional fine tuning.
  - **Ground:** ten patterns (dots, squares, bold, plus, hearts, stars, checks, lines, grid, none), pool colour, moving pools full, soft or still.
  - **Shape:** corners (stepped, deep, round, sharp), cards (filled, outline, tinted), titles (phone, classic, pixel).
  - **LAR:** his colour, or the school's. The Dive preview shows the tunnel in this theme.
  - **Share:** name, share card, save, scan.
  - **The dice** on the preview rolls a whole theme and a name.
  - *Built 2026-11-09 (`src/lib/ThemeMaker.svelte`, `theme.ts`):* a full-screen page with Back in the preview's top row (Android back closes it too), opened by `app.themeMaker`. The page wears the theme being made; the app wears it once saved. Presets and saved themes share the Colour row. Share has name, share card, Save, and Add a code (scan waits for the camera, C18). The Dive tab draws the tunnel preview in the theme's accent and pool hues; the real dive is unchanged. LAR's colour reaches him across the app. The Pixel and Classic title picks set `--font-display`; Phone leaves the text style in You in charge.
- **C13.** Every theme goes through the clamps when applied: text at least 7:1 on cards, quieter text 4.5:1, the accent 3:1. The student's picks can't make it unreadable.
  - *Built 2026-11-09 (`roles` in `theme.ts`):* the ground and cards are first pushed to the theme's side of light until 7:1 text exists on them, so any fine-tuned colour works; text is also 7:1 on the ground, subject colours 3:1, good and bad 4.5:1. Tinted cards are the card mixed 14% with the accent, and outline cards are filled with the ground colour (kept opaque, per the Living Ground Rule), so the clamps measure the real fill.
- **C14.** Saved themes sit beside the rooms and can be renamed or deleted. Deleting the active one falls back to Night.
  - *Built 2026-11-09:* they show after the four hand-tuned rooms in You, as room ids `theme:<id>`, stored in `localStorage` under `themes` as share codes (so storage gets the C17 check too). Rename is the name field and Save; Delete asks first. A room naming a missing theme wears Night. Erase everything forgets them. Backup (C9) isn't built yet.
- **C15.** A theme applies to the whole app, including derived subject colours and the ground. The landing and the portal keep their own world.
  - *Built 2026-11-09:* `setRoom` hands the saved theme to `applyRoom`, which sets every role, `--pattern`, `--aura-o` and the titles on the root, plus `data-corners` and `data-cards`. Corners act on `.notch` surfaces (Deep 6 px steps, Round 16 px radius, Sharp square).

**Sharing**
- **C16.** Share gives a code and a QR of it. Format `IPT1.` plus base64url of: version, choices (pattern, moving pools, corners, cards, titles), two hues, four RGB colours, name length, name (at most 24 characters), and a checksum byte. The code sits on a theme card with the QR, in the theme's own colours.
  - *Built 2026-11-09 (`themeCode.ts`), byte for byte as the picks page:* version byte 2; flags = pattern (4 bits) | pools << 4 | corners << 6; flags2 = cards | titles << 2; pool hue and LAR hue in 255 steps (LAR 255 = the school's); accent, ground, card, ink; name length; UTF-8 name; checksum = sum of all bytes mod 256. The QR is drawn as one SVG path by `qrcode-generator` (MIT, error correction M, four-module quiet zone). Copy code uses the clipboard; the code text is selectable if that is blocked.
- **C17.** A code holds only the C16 fields: the theme's look and a name, with nothing that runs or links. Decoding validates length, version and checksum, and the name is shown as plain text and never as markup.
  - *Built 2026-11-09:* decoding also refuses unknown choice values, unused flag bits, bad base64, a name that isn't UTF-8, over 24 characters, or holds control or direction-changing characters. The name is only ever a Svelte text node: no `{@html}`, never a URL or attribute.
- **C18.** Add a theme by pasting a code or photographing its QR. The student sees it first and chooses Keep or Not now. A bad code changes nothing and says so.
  - *Built 2026-11-09:* paste only. The maker takes on the pasted theme while Keep or Not now is open; Keep saves and wears it, Not now puts back what was there. Photographing waits for the camera plugin (#219): `scanQr` in `themeCode.ts` is the hook, null for now, and the photo button appears once it is set.
- **C19.** Sharing needs no network and no account. Nothing about the student is in the code.
  - *Built 2026-11-09:* encoding, decoding and the QR all run on the phone; the code holds only the C16 fields.

## Copy

As on the picks page. Final strings go here after the picks.

## Data shape

- Themes: `{ name, accent, ground, card, ink, hue2, lar, pattern, aura, corners, cards, titles }`, stored with settings and included in backups. They survive sign-out, and Erase everything removes them.
- `src/lib/rooms.ts`: `derive` gains a path from a theme; `applyRoom` accepts a saved theme's id. `themeCode.ts`: `encodeTheme`, `decodeTheme`.
- QR drawing: `qrcode-generator` 2.0.4 (MIT, checked; no dependencies; its ES module is 52 KB unminified, 11 KB gzipped).
- QR scanning: the one camera plugin, shared with Scan (#197) and 046's photos, owned by the Head. `plugin:camera|capture` with `{ source: "camera", read: { qr: true } }` takes one photo and keeps nothing; there's no live scanner. Until it lands, paste works alone. If the user chooses Play services for Android's reader, the first QR read needs a one-time download, so 047 adds an offline line then.
- Backup commands: `src-tauri/src/lib.rs` is a hot file, so they go in one small PR.

## Errors

- Bad code: "That code doesn't look right, so nothing changed. Ask for it again."
- No camera permission: a line on how to allow it, with paste offered.
- Backup can't be written or read: says which, and changes nothing.

## Motion and Reduce Motion

Pages slide in over 0.26 s with the shared ease. Quick switches press and `SAVED` stamps with the shared ease. Reduce Motion skips to rest. Haptics: `select` on a segment, `tick` on a switch, `done` on Save and Keep.

## Accessibility

Rows and switches are at least 48 pt, or 44 pt in Compact, with names and states read out. Colour sliders have values read out and are never the only way to set a colour: fine tuning takes a colour picker. Contrast clamps cover the rest.

## Test map

| Criterion | Test |
|---|---|
| C2 | `vitest`: `c2_search_finds_every_setting` |
| C5–C8 | `vitest`: settings round trip, `c6_every_card_can_hide_and_move` |
| C9, C10 | `cargo`: `c9_backup_has_no_logins`, `c10_bad_backup_changes_nothing`, `c10_other_students_backup_refused` (including nobody signed in), `c9_backup_keeps_own_deadlines_and_done` |
| C13 | `vitest`: `c13_every_theme_meets_contrast` over a sweep of colours |
| C16, C17 | `vitest`: `c16_code_round_trip`, `c17_bad_code_refused` (cut, tampered, wrong version, markup in the name) — `src/lib/theme.test.ts` |
| C14 | `vitest`: deleting the worn theme falls back to Night — `src/lib/theme.test.ts` |
| C1, C3, C4, C12, C18 | screenshot, real phone |
