# 046 Study and notes

**Status:** draft. Every look is picked (round two, 2026-11-05, on the [study picks page](reference/prototypes/study-you.src.html)). The Head's review fixes are in. Three questions at the end are still the user's.

## What changes for the student

Notes stop being a flat list at the bottom of Study. Each subject holds its own notes and decks, and a note can have headings, checklists, highlights and photos, start from a template, and turn into flashcards in two taps.

## Direction and references

- User's answers, 2026-11-05: sorted by subject; formatting, templates, photos and note to cards all in the first version; quiz from notes comes next.
- Style: spec 045, Pixel-bridged type, stepped cards, one accent. Play wraps the data; note text stays calm.
- Editor: the user's own PUPNotes (`IntPortal/notes-editor`, CodeMirror 6), issue #20. Port only what these criteria need.
- Spec 030 stays the parity map. C11–C14 there are *removed*, pointing here, as C6–C10 point to 041; rows 26–33 point here too (#146). 030 C1–C5 stay in 030.
- Issues: this spec re-scopes #20 to the live editor it describes. #147 keeps C1 and C2 and #149 keeps C3–C5, with their entry criteria moving here.
- Out of scope: spec 022 and #142 (quiz from notes) stay with the AI engineer; 046 leaves a place for its entry point. Row 33 (which notes the AI reads) touches `rag.rs` and needs the Code engineer's agreement, so it stays out for now.
- Settled picks in `PLAN-dive-environment.md` apply: nothing rises or spawns in after a transition, and readability beats pixel font on small data.

## Keep

- Keys `class:`, `day:` and `note:`, one class note across weeks, one day note per day. `notes::is_known_key`, the RAG `note_key` and the 042 deep link `note:class:<code>` depend on them, so subjects and pins are metadata and never part of a key.
- Note text is plain Markdown. `notes_markdown`, RAG chunks and Ask AI (`appended`, `replaced`) read it as text.
- Save while typing and on Done. Delete with its confirm (040 C8). A row always has text: blank text deletes the note and its AI chunks (`store.set_note`), and the class sheet, the Schedule dot, Today's day note, the Delete button and 042 all read a row as "has notes". Share as `.md`, Export all.
- Ask AI in a note, source chips, the AI index over note text. AI stays on-device and rules first, and writes nothing without a tap.
- The after-class prompt only fires for subjects whose `class:` note has text (042 C8, C9).
- Due count, streak, today's count, Review all (040 C9), New deck, DeckPage, FSRS.
- Opening a note from Today, a class sheet, a notification or a subject page.

## Behaviour

**Sorted**
- **C1.** Study is a notebook shelf (picked 2026-11-05): one notebook per subject from the student's classes, plus General. Pulling one out shows its notes and decks below.
- **C1a.** A notebook's window holds one pixel per note and one beating gold pixel per card due, up to 15, and a fuller notebook stands taller. The beat is a slow opacity change in CSS, with no canvas, and it stops under Reduce Motion and while the model runs (#189). Every other pixel moves only when the data changes, on a pull, or in a rare twinkle. The counts are also written in reading type, and read out by VoiceOver. *Details are in round two.*
- **C1b.** One floating button, the crystal (picked 2026-11-05): a real 3D 3x3x3 cube of obsidian glass, dark in every room. Lit cubes are windows onto the school's portal (the dive's tunnel, in its five tones, through the 4x4 Bayer dither), each standing for data. It reflects the room's dot grid and carries LAR's sheen. Cubes that leave during the fold dissolve in the same dither. It replaces the pixel gem. On Study and in the note editor it folds into a + of the same glass, on a spring of about 0.7 s, and turns 45 degrees into a close mark while its menu is open. Every control can scroll clear of it: each page's bottom padding is at least the chip's top plus 8 pt. Today the orb starts at `safe-bottom + 84` and pages pad `safe-bottom + 92`, or +142 and +150 with the dock, so with a 48 pt chip the padding rises to +140 and +198 in `ui/crystal`. On Today, Done and Undo sit on the left of the row, away from it. Ask LAR is the first item in the + menu on those screens. While LAR thinks, a query sweeps through the cubes, or through the + on those screens.
- **C1b2.** At rest it belongs to the UI. It is a 48 pt stepped chip on the page's gutter, like the app's other controls, with no shadow, bob or glow. The cube inside is a true isometric view in exact room tokens: three flat tones of the card colour, card hairlines, and one gold dot on each cube that holds data. The + is flat, in the room's gold, per the One Gold Rule. About 2 s after the last movement (a scroll, a tap, a tab change, the end of LAR's work) it settles through the dither and draws nothing until it wakes. Scrolling, tapping or LAR thinking wakes the glass in about 0.2 s. Reduce Motion shows the rest state only.
- **C1b3.** While LAR thinks, the cube does not spin faster. Its 27 boxes rearrange every 1.5 to 2 s into something being mapped: a random neuron, roots, a helix or a lattice, with a signal running out from the centre. It keeps turning slowly. This also happens from the +.
- **C1b4.** When LAR finishes, a small moment in the ground, behind the cards: thin roots grow out along the dot grid from the crystal, about four trunks with a few branches, data runs back along them, the crystal gives one small pulse, and the roots fade. About 1.5 s. Reduce Motion skips it.
- **C1c.** The crystal only shows as a cube once LAR's model is installed (`installed()`). Without it, Study and the editor show the + and other tabs show nothing. It keeps `data-orb` (`AssisSheet.svelte:68` reads its position for the flight to LAR, which is checked from each position).
- **C1d.** Drawn with WebGL2 in one small canvas, with no new library: at most 30 frames a second while awake and no frames at rest, stopped when hidden (`class:away`, so LAR's sheet being open draws nothing), off-screen or backgrounded. Without WebGL2, or under Reduce Motion, it is a still image, and the morph is skipped.
- **C1d2.** On a low-RAM phone, the tier #188 and #189 stall on, thinking keeps the rest state with a cheap CSS sweep across it, with no WebGL, neuron forms or roots (C1b3, C1b4). *This is a real-phone check before it ships, including a low-end Android (#189).*
- **C2.** A class note belongs to its subject by its key, with no second field to disagree with it. A freeform note carries a subject, chosen on creation and changeable in the note. The editor holds the choice until the first save with text. No subject means General.
- **C3.** Day notes go under General, newest first, and can't be moved.
- **C4.** Inside a subject: pinned notes first, then newest edit first, then that subject's decks with their due counts.
- **C5.** Long press a note, or use its menu, to pin or delete, and to move a freeform note to another subject. Delete keeps its confirm (040). Pinning or moving doesn't change the note's edit time, so it neither jumps the list nor re-indexes the note for AI.
- **C6.** Search covers every note's name and text, and every deck's name, across subjects. It works offline.
- **C7.** A subject code can outlive its term. Once it leaves the schedule, its notes and decks stay together under the code alone, in a Past subjects group, with no description. Nothing is lost on a new term.
- **C8.** Notes stay reachable from You (040 C14). *The user built that placement: keep, port or drop is theirs, asked 2026-11-05. Until they answer, it stays.*

**Writing**
- **C9.** The note shows formatted as it is typed: headings, bold, highlight, bullets, checklists. A line's Markdown marks appear only while the cursor is on it. The build PR states CodeMirror 6's measured bundle size.
- **C10.** The saved text is plain Markdown, with `==text==` for highlight and `- [ ]` for checklists, so Share, Export and the AI index keep working.
- **C11.** One floating crystal +, the same as on Study, opens a sheet of Ask LAR first, shown only when `installed()`, then 15 tools: heading, bold, italic, highlight, strike, bullets, numbers, checklist, quote, code, divider, date entry, photo, template, make cards. Selecting text shows a small bar of bold, italic, highlight and strike.
- **C11a.** Page settings (Aa): text size, font (Phone, Classic, Mono), line spacing, paper (plain, lines, dots, grid), what a new note starts as, word count, keep the screen awake while writing. They apply to every note, and they change how the page looks, never its Markdown.
- **C11b.** This note (the dots): pin, move to a subject, find in note, share with its word count, delete with its confirm. Undo and redo sit in the top bar.
- **C11c.** Tool icons are the hand-placed 12 by 12 set on the picks page: chunky stems and one gold accent. Only the crystal is 3D.
- **C12.** Ticking a checklist box saves at once, without opening the keyboard. A tick is an edit: the note moves to the top of its subject and is re-read for AI on the next index.
- **C12a.** When LAR adds to a note that is open in the editor, his text appears in it. The editor's next save never overwrites it.
- **C13.** A new note offers Blank, Lecture, Cornell, Exam reviewer and Dated log. A template on a note with text adds below it and never replaces it.
- **C14.** Add entry (030 C11–C14): Dated log and class notes add a dated heading with one tap and put the cursor on the line after it. The date is today when the class meets today, otherwise its next meeting, skipping vacant weeks and following moved meetings, and a class with no future meeting uses today. The heading reads `### Mon, Oct 20` in the phone's locale. If the note already ends with that date's heading, the cursor moves there and nothing is added. The date comes from the core, tested. The editor only inserts the heading.
- **C14a.** The after-class prompt's tap opens the class note on that meeting's dated entry, finishing what 042 C8 and C9 left waiting on Add entry.

**Photos**
- **C15.** A note can hold photos from the camera or the library, shown in a strip below the text, each at most 1600 px on its long side. A photo has no position in the text, so it can't sit between two paragraphs.
- **C16.** Photos are kept apart from the note's text, so they never reach AI chunks or prompts. The app never sends them anywhere; the student can share or export them. How they are kept depends on the user's pick below, and no copy may claim more than it does: as store rows, they are encrypted and go wherever the store goes (on iOS the store isn't excluded from device or iCloud backups, so they're in those, encrypted, and count toward the student's iCloud space; Android has `allowBackup="false"`). As plain files, they sit unencrypted in private storage and are left out of backups.
- **C17.** Deleting a note or erasing everything deletes its photos, and an orphan sweep clears any left behind. Sign-out keeps them, like notes. Share and Export carry them as a zip when a note has photos, and say so. That comes from the note's photo count, because nothing in the text marks them.
- **C17a.** Autosave doesn't save while the text is blank. Closing the editor with blank text deletes the note, so select-all and retype loses nothing, and if the app is killed mid-edit the old text comes back. A pin or subject goes with a deleted note. Sign-out closes the editor without saving, and the old text survives.
- **C15a.** A note holds at most 20 photos, and adding a 21st says so. Adding a photo moves the note up its subject, like any edit.
- **C17c.** *Photos phase.* A note can hold only photos, with no text. Adding a photo to a note with no row creates the row in the same transaction, with empty text and the held name and subject. A note with photos isn't deleted by blank text, from autosave or on close: the core checks this in one transaction, and its row stays, with the text and its AI chunks removed in the same call, so LAR can't cite erased words. Everything that reads a row as "has notes" counts this note as having notes only because of its photos, and the export skips its empty section. Delete asks first and removes the photos, in one transaction with the note, so a crash can't leave it half deleted.
- **C17d.** *Photos phase.* A note with photos and no text shows "3 photos" in lists. The Schedule dot and the class sheet count photos as notes. The after-class prompt (042 C8, C9) still needs text. Ask AI and Make cards on a note with no text say there's nothing to read, without calling the model.
- **C17b.** When a photo can't be taken or saved, one line says so and how to fix it (`cameraProblem()`), and the note is untouched.

**Note to cards**
- **C18.** Make cards marks lines to choose from. Lines written `term - meaning` start chosen. No AI model is needed.
- **C19.** A review step shows each card's front and back, editable, and which deck they go to: the subject's deck, or a new one named after the subject.
- **C20.** Nothing is saved until Save cards. Fronts the deck already has are dropped, using `tidy` in `assis/cards.ts`.
- **C21.** With a model installed (`installed()`), Ask AI cards (`DeckCards`) still works and goes through the same review.

**A Done you can find**
- **C22.** Each row on the Due card has a visible Done control with the word Done, and nothing covers it (found 2026-11-05: `AssisOrb` sat on the first square). It is on the left of the row, and marking done is the run in 045 C18 (#221). The first time a student has a deadline, LAR says one line about it, once.

## Copy

As on the picks page. Final strings go here after the picks.

## Data shape

- `crates/intportal-core/src/notes.rs`: `Note` gains `subject: Option<String>` (only `note:` keys use it, a code that may outlive its term) and `pinned: bool`. Older notes read as none and false.
- `store.rs`: the first migration in `Store::init`, which today only runs CREATE TABLE IF NOT EXISTS. `ALTER TABLE notes ADD COLUMN subject TEXT` and `pinned INTEGER NOT NULL DEFAULT 0`, each guarded by `PRAGMA table_info(notes)`, because a blind ALTER fails on the second open and the store then won't open. A test opens an old-schema file. A migration error stays an ordinary error and is never `Locked`, because `open_store` renames a Locked file aside and opens a fresh store, which would look like a wipe. `notes()` lists the columns; the dead `stale_notes` is removed.
- New commands `set_note_pin(key, bool)` and `set_note_subject(key, Option<String>)`, so a stale list that pins can't undo a move. Neither bumps `updated` (chunks are fresh only when `note_updated = updated`), and `set_note`'s upsert doesn't touch them. Both return an error on a missing key and never create a row. `set_note_subject` rejects `class:` and `day:` keys. The editor calls `set_note`, then these; a crash between them leaves the note in General.
- `notes::preview` strips `- [ ]`, `- [x]` and `==` as well.
- Sort pinned-first in the list the UI reads. `notes()` keeps its order for RAG and `notes_markdown`.
- Tags: not in this spec. They'd need their own table.
- Photos: an attachments table (`id, note_key, file, w, h`) and a folder per student so another student on the phone can't see them. `wipe` only clears tables today, so it must remove the folder too. Write the file first, then the row. The orphan sweep removes only files with no row that are older than a day, in the current student's folder. `Store::wipe` doesn't know the path, so the erase command in `lib.rs` removes the folder. Display is bytes through a command as `tauri::ipc::Response`, then a Blob URL revoked when the note closes, with no `tauri.conf.json` change. `notes_markdown` returns one String, so a note with photos exports through a new zip path.
- If photos are rows: photo commands are async with `spawn_blocking` and return bytes through `tauri::ipc::Response`, because sync commands run on the main thread and a waiting one freezes the UI. Deleting a note is one transaction, bounded by C15a's cap: about 110 ms for 20 photos on a Mac, estimated 0.3-1 s on a low-cost phone. Larger jobs (zip export, 047's backup) take one photo per lock and release between; 500 in one statement took 2.7 s on the Mac. Lists never select `bytes` and read by an indexed `note_key`. Deleting doesn't shrink the file, and new photos reuse the space: Erase everything VACUUMs after clearing (22 ms when empty), and normal use never VACUUMs. `wipe` gets `DELETE FROM photos`; `forget_sis` leaves them.
- Ownership: `store.rs` and `lib.rs` belong to the Core role and are hot, so this goes to the Code engineer as an issue.
- Lifetime: subjects, pins and photos survive sign-out (`forget_sis` doesn't touch them), and Erase everything removes them (`store.wipe`).
- Entry date: `entry_date(sessions, marks, code, today)` in `notes.rs` or `today.rs` (030 C12).
- Commands: `src-tauri/src/lib.rs` is a hot file, so new commands go in one small PR.
- Camera: one plugin, shared with Scan (#197) and 047's QR, on `core/camera-plugin`, owned by the Head. `plugin:camera|capture` takes `{ source: "camera" | "library", read?: { text?, qr? }, saveTo? }` and returns `{ cancelled, path?, width?, height?, text?, qr? }`. It rejects with `camera_denied`, `no_camera`, `no_space`, `save_failed`, `bad_photo`, `bad_folder` or `busy`, and a cancel is not an error. Use `capture()` and `cameraProblem()` from `src/lib/camera.ts`.
- `saveTo` is an absolute folder inside the app's data directory. The plugin names the file and writes a JPEG of at most 1600 px on the long side, so downscaling happens there and not in the WebView. On iOS it sets `isExcludedFromBackup` and file protection.
- A new core command returns the per-student photo folder to pass as `saveTo`.
- `src/lib/api.ts`: `NoteItem` follows; `setNote` keeps its contract.
- Export: subject and pin stay out of the Markdown, which goes to classmates when shared. 047 C9's backup carries them.
- If photos are encrypted files: `XChaCha20Poly1305` from `chacha20poly1305` (pure Rust), a 24-byte random nonce from `getrandom`, the attachment id as associated data so files can't be swapped, and a second random key per student under the same keychain service as `dbkey`, not the SQLCipher key.

## Errors

- Photo can't be taken or saved (any `cameraProblem()` code): the note keeps its text, a line says why and how to fix it.
- A saved note's photo is missing: a quiet placeholder with the file's name, and the rest of the note reads normally.
- Cards can't be saved: the review stays open with what was typed.

## Motion and Reduce Motion

A notebook pulled out changes the layout, so it opens over `--t-flow` (0.36 s) with the shared ease; a sheet rising uses the shared ease and spring, 0.3 s. What the notebook shows below it is simply there: nothing rises or spawns in after it. Checklist boxes and the `+N CARDS` stamp stay in place, so they may use `steps()`, and they are named exceptions to the Smooth Travel Rule. Reduce Motion skips to the resting state. Haptics: `select` on a subject, `tick` on a checklist, `done` on Save cards.

## Accessibility

Every tool and row has a 44 pt target and a name. Checklist boxes are real controls with their state read out. Note text follows the iOS text size to the body cap. Subject colours are never the only way to tell subjects apart: the code is always written.

## Test map

| Criterion | Test |
|---|---|
| C2, C3, C4, C7 | `vitest`: `c4_subject_shelves_sort_pinned_then_newest` and siblings; `cargo`: note round trip with subject and pinned |
| C1b2, C1c, C1d, C1d2 | `vitest`: `c1b2_settles_and_wakes`, `c1c_no_cube_until_installed`, `c1d2_low_ram_never_starts_webgl`; real phone for the look |
| C1b | `vitest`: `c1b_page_padding_clears_the_chip` |
| C6 | `vitest`: `c6_search_across_subjects` |
| C10 | `vitest`: `c10_markdown_round_trip` |
| C13, C14 | `vitest`: `c13_template_never_replaces`, `c14_entry_not_repeated`, `c14_heading_in_the_phones_locale`; `cargo`: `c14_entry_date_skips_vacant_follows_moved`, `c14_no_future_meeting_uses_today` |
| C14a | `vitest`: `c14a_after_class_opens_the_entry` |
| C12a | `vitest`: `c12a_lar_text_survives_autosave` |
| C17a | `vitest`: `c17a_blank_never_autosaves`, `c17a_blank_on_close_deletes` |
| C15a | `cargo`: `c15a_21st_photo_refused` |
| C17c | `cargo`: `c17c_kept_row_drops_its_chunks`, `c17c_blank_keeps_a_note_with_photos`, `c17c_first_photo_creates_the_row`, next to `c8_delete_note_drops_chunks`; Delete removes the photos |
| C17d | `vitest`: `c17d_photo_only_preview`, `c17d_after_class_needs_text`; `cargo`: empty `notes_markdown` section |
| Data | `cargo`: `old_schema_opens_and_gains_columns`, `migration_error_is_not_locked`, `pin_and_subject_keep_updated`, `meta_on_missing_key_errors`, `subject_refused_on_class_and_day`, `preview_strips_checklist_and_highlight` |
| C16, C17 | `cargo`: `c17_note_delete_removes_photos`, per-student folder |
| C18–C20 | `vitest`: `c18_term_lines_start_chosen`, `c20_duplicates_dropped` |
| C9, C11, C12, C15, C22 | screenshot, real phone |

## Open questions

- "Add fonts for the cube": the user asked for this and it isn't clear what it means. Nothing is built for it.
- Mathematics and tables in notes: offered, not requested.
- C8: notes on You: keep, port to a row, or drop?
- Photo storage, for the user. The store is SQLCipher-encrypted, and plain files sit outside it. Options:
  - Rows in the store (recommended): a separate table of JPEG BLOBs loaded only when shown. No new crypto, key or orphan sweep; per-student, erase and atomic delete come free. Measured on a Mac with a real store, 0.5 MB photo, flat from 0 to 500 photos: insert 17-19 ms, read 2-4 ms, delete 25-34 ms. Estimated on a low-cost Android, not measured: insert 60-200 ms, read 15-50 ms, delete 100-300 ms. Bulk work is the risk, see the rules in Data shape.
  - Files encrypted with a new crate: photos stay out of the store and don't hold its lock. Costs: our own key and nonce handling, plus a sweep for orphans.
  - Plain files in private storage, left out of backups: cheapest and weakest, and no encryption claim.
- With either encrypted option, the plugin saves to a temp folder under the app's data directory (`tmp` and `Caches` are refused on iOS), and the core takes the file in and deletes it. A launch sweep and Erase everything clear that folder. Deleting doesn't guarantee the plain file is gone from flash, so the claim is "encrypted after a moment as a plain file", never "never on disk". Avoiding that entirely needs a plugin mode that returns bytes, which the Head can add if asked.
- Whichever is picked, photo references stay out of the note's text (C16), so they never reach AI chunks. The strip reads them by note key.
- Strip or between paragraphs: the mockup shows a strip, which keeps the text clean for AI. A photo beside a specific paragraph would need references in the text, so it's the user's call if they care.
- C15a's cap of 20 is a proposal, sized by the delete timing above.
- Photos are the largest piece, so they ship in their own later phase, with the camera plugin.
