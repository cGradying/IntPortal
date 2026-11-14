# 046 Study and notes

**Status:** shipped (2026-11-14). Every criterion is built; the camera and library paths (C15, C17b) still wait for a check on the simulator and a real phone. Approved 2026-11-05: the user took the recommendations, photos are rows in the store, and notes on You are a short row.

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
- Due count, streak, today's count, Review all (040 C9), New deck, DeckPage, FSRS. Since the tiles home they live on the Review and Cards parts (C1).
- Opening a note from Today, a class sheet, a notification or a subject page.

## Behaviour

**Sorted**
- **C1.** Study opens on a home of part tiles (picked 2026-11-09, round three A, "Tiles home"), always on the home. Each tile shows live data and opens its own page with "‹ Study" as the way back, which the phone's back gesture also takes. A page slides in 28 px over `--t-flow` with the shared ease, from the right going in and from the left coming back; under Reduce Motion it cross-fades in place. Each part fits about one phone screen.
  - **Review:** cards due now in pixel numerals, a gold pixel per card due (up to 30), the streak and today's count. Its page lists every deck with its due pixels and count, the streak and today, and "Review N due", which starts the all-due session (040 C9).
  - **Notes:** a little shelf, each notebook lit as on the real one (C1a), and the note and notebook counts. Its page is the notebook shelf (picked 2026-11-05): one notebook per subject from the student's classes, plus General. Pulling one out shows its notes below.
  - **Cards:** a bar per deck, one pixel per 3 cards with the due ones gold, and the deck and card counts. Its page lists decks grouped by subject in shelf order, with their due counts, and New deck. Tapping a deck opens DeckPage.
  - **Done** (the user kept it, 2026-11-09): a wide tile of seven small bars, a pixel per 3 cards reviewed each day, today in gold, and the week's total. Its page shows the bars larger with each weekday, the total, the streak and today. The counts are the core's reviews per local day (#239, `StudyOverview.week`). The mockup's session log is not shipped; the core keeps counts per day, not sessions.
  - The + offers New note (in the notebook last pulled out), Today's note and New deck, which opens Cards with the form.
- **C1a.** A notebook's window holds one pixel per note and one beating gold pixel per card due, up to 15, and a fuller notebook stands taller. The beat is a slow opacity change in CSS, with no canvas, and it stops under Reduce Motion, while the model runs, behind LAR's sheet and while hidden (#189). Every other pixel moves only when the data changes, on a pull, or in a rare twinkle. The counts are also written in reading type, and read out by VoiceOver. *Details are in round two.*
- **C1b.** One floating button, the crystal (picked 2026-11-05): a real 3D 3x3x3 cube of obsidian glass, dark in every room. Lit cubes are windows onto the school's portal (the dive's tunnel, in its five tones, through the 4x4 Bayer dither), each standing for data. It reflects the room's dot grid and carries LAR's sheen. Cubes that leave during the fold dissolve in the same dither. It replaces the pixel gem. On Study and in the note editor it folds into a + of the same glass, on a spring of about 0.7 s, and turns 45 degrees into a close mark while its menu is open. Every control can scroll clear of it: each page's bottom padding is at least the chip's top plus 8 pt. Today the orb starts at `safe-bottom + 84` and pages pad `safe-bottom + 92`, or +142 and +150 with the dock, so with a 48 pt chip the padding rises to +140 and +198 in `ui/crystal`. On Today, Done and Undo sit on the left of the row, away from it. Ask LAR is the first item in the + menu on those screens. While LAR thinks, a query sweeps through the cubes, or through the + on those screens.
- **C1b2.** At rest it belongs to the UI. It is a 48 pt stepped chip on the page's gutter, like the app's other controls, with no shadow, bob or glow. The cube inside is a true isometric view in exact room tokens: three flat tones of the card colour, card hairlines, and one gold dot on each cube that holds data. The + is flat, in the room's gold, per the One Gold Rule. About 2 s after the last movement (a scroll, a tap, a tab change, the end of LAR's work) it settles through the dither and draws nothing until it wakes. Scrolling, tapping or LAR thinking wakes the glass in about 0.2 s. Reduce Motion shows the rest state only.
- **C1b3.** While LAR thinks, the cube does not spin faster. Its 27 boxes rearrange every 1.5 to 2 s into something being mapped: a random neuron, roots, a helix or a lattice, with a signal running out from the centre. It keeps turning slowly. This also happens from the +.
- **C1b4.** When LAR finishes, a small moment in the ground, behind the cards: thin roots grow out along the dot grid from the crystal, about four trunks with a few branches, plus one trunk up the page's open right gutter so it shows on a screen full of cards, data runs back along them, the crystal gives one small pulse, and the roots fade. About 1.5 s. Reduce Motion skips it.
- **C1c.** The crystal only shows as a cube once LAR's model is installed (`installed()`). Without it, Study and the editor show the + and other tabs show nothing. It keeps `data-orb` (`AssisWindow.svelte` reads its position to anchor LAR's window and moves it to ride the glass; checked from each position).
- **C1d.** Drawn with WebGL2 in one small canvas, with no new library: at most 30 frames a second while awake, full rate only while it folds, pulses or turns for the menu, which are all brief, so they stay smooth, and no frames at rest, stopped when hidden, off-screen or backgrounded. Without WebGL2, or under Reduce Motion, it is a still image, and the morph is skipped. **It opens LAR's window** (round three C2, the opening reworked 2026-11-14): tapping it, the chip hides and the window dithers out of it as a 4×4 Bayer pixel dissolve (spec 048 C1–C3), so the open window draws no crystal frames and there is never a second WebGL context. Closing dithers the window back into the chip, which reappears as the last cells go (048 C6). Reduce Motion cross-fades. State: `chip.at` in `AssisWindow.svelte`. *2026-11-14: the owner kept the dither opening and asked for the 3D crystal back (#271 reverted).*
- **C1d2.** On a low-RAM phone, the tier #188 and #189 stall on (`models::is_small_ram`, under 6.5 GB), WebGL never starts: the fold is skipped, and thinking keeps the rest state with a cheap CSS sweep across it, with no neuron forms or roots (C1b, C1b3, C1b4). The chip still opens LAR's window with the same dither (048 C1–C6); the tier is assumed until the phone answers. *This is a real-phone check before it ships, including a low-end Android (#189).*
- **C1d3.** *Replaced by spec 048 C12–C15 (2026-11-10): LAR's steps are a pixel trace in CSS, and sources light in pixel corners; `neuron.ts` is removed.* Was: the neuron in LAR's window (picked 2026-11-09, round three C2), on one canvas over the page: while LAR thinks (waking, thinking, making cards), dendrites grow from his antenna's spark through the window's nine cells, lighting each cell they cross, and signals run in to him. When an answer with sources arrives, the axon grows out of the glass to its From chips, and to each source's note on the page behind the window when it is on screen (`data-source`), signals run out along it and ring each source in a stepped outline, then it fades (about 3 s). An answer with no source fires a short spark inside the glass only. At most 30 frames a second, nothing drawn at rest, paused while the app is hidden; Reduce Motion shows one still, lit frame. Geometry in `assis/neuron.ts`, seeded.
- **C2.** A class note belongs to its subject by its key, with no second field to disagree with it. A freeform note carries a subject, chosen on creation and changeable in the note. The editor holds the choice until the first save with text. No subject means General.
- **C3.** Day notes go under General, newest first, and can't be moved.
- **C4.** Inside a subject: pinned notes first, then newest edit first. The subject's decks are on the Cards part, under its code, with their due counts (C1).
- **C5.** Long press a note, or use its menu, to pin or delete, and to move a freeform note to another subject. Delete keeps its confirm (040). Pinning or moving doesn't change the note's edit time, so it neither jumps the list nor re-indexes the note for AI.
- **C6.** Search on Notes covers every note's name and text, and every deck's name, across subjects. It works offline. A deck found there opens its deck page (the user kept decks in search, 2026-11-09).
- **C7.** A subject code can outlive its term. Once it leaves the schedule, its notes and decks stay together under the code alone, in a Past subjects group, with no description. Nothing is lost on a new term.
- **C8.** Notes stay reachable from You (040 C14), as a short row that opens them (the user, 2026-11-05).

**Writing**
- **C9.** The note shows formatted as it is typed: headings, bold, highlight, bullets, checklists. A line's Markdown marks appear only while the cursor is on it. The build PR states CodeMirror 6's measured bundle size.
  *Built 2026-11-11:* CodeMirror 6 (`src/lib/editor/cm.ts`) with the Lezer Markdown parser and GitHub's extensions, not `lang-markdown`, which would bring HTML, CSS and JS parsers. Headings, bold, italic, strike, inline code, quotes, code blocks, dividers, bullets (a gold dot) and checklists show formatted; a line's marks show only while the cursor is on it. It loads with the first note opened: 98.7 kB gzipped (306.8 kB minified) in its own chunk; the app's first load grows 6 kB.
- **C10.** The saved text is plain Markdown, with `==text==` for highlight and `- [ ]` for checklists, so Share, Export and the AI index keep working.
  *Built 2026-11-11:* every edit is a pure function on the Markdown in `src/lib/editor/md.ts`; the store still holds plain text.
- **C11.** One floating crystal +, the same as on Study, opens a sheet of Ask LAR first, shown only when `installed()`, then 15 tools: heading, bold, italic, highlight, strike, bullets, numbers, checklist, quote, code, divider, date entry, photo, template, make cards. Selecting text shows a small bar of bold, italic, highlight and strike.
  *Built 2026-11-11:* the crystal is the +: the editor mounts inside the tab shell's stacking context, the crystal sits above it at the bottom right, and its press opens the editor's sheet (`assis.plus`). The sheet has Ask LAR first (only with a model), then the 15 tools. Photo shows "Soon" until the Photos phase (C15). Selecting text shows bold, italic, highlight and strike at the top right.
- **C11a.** Page settings (Aa): text size, font (Phone, Classic, Mono), line spacing, paper (plain, lines, dots, grid), what a new note starts as, word count, keep the screen awake while writing. They apply to every note, and they change how the page looks, never its Markdown.
  *Built 2026-11-11:* kept on the phone as `notePage`. Keep awake uses the Wake Lock API where the webview has it, and asks again each time the app comes back on screen.
- **C11b.** This note (the dots): pin, move to a subject, find in note, share with its word count, delete with its confirm. Undo and redo sit in the top bar.
  *Built 2026-11-11:* pin, move (freeform notes only: class notes are filed by their class), find (Next jumps to the next match, wrapping), share with its word count, delete with its confirm. Undo and redo are CodeMirror's history.
- **C11c.** Tool icons are the hand-placed 12 by 12 set on the picks page: chunky stems and one gold accent. Only the crystal is 3D.
  *Built 2026-11-11:* the 20 missing tool icons were copied from the picks page into `PixelIcon`.
- **C12.** Ticking a checklist box saves at once, without opening the keyboard. A tick is an edit: the note moves to the top of its subject and is re-read for AI on the next index.
  *Built 2026-11-11:* a box is a real button that never takes focus; the tick is saved at once.
- **C12a.** When LAR adds to a note that is open in the editor, his text appears in it. The editor's next save never overwrites it.
  *Built 2026-11-11:* `mergeExternal`: LAR's addition goes after what is on screen, and the next save keeps both.
- **C13.** A new note offers Blank, Lecture, Cornell, Exam reviewer and Dated log. A template on a note with text adds below it and never replaces it.
  *Built 2026-11-11:* a new note opens on Start from, unless Aa says Blank or Last used. Dated log starts with today's entry.
- **C14.** Add entry (030 C11–C14): Dated log and class notes add a dated heading with one tap and put the cursor on the line after it. The date is today when the class meets today, otherwise its next meeting, skipping vacant weeks and following moved meetings, and a class with no future meeting uses today. The heading reads `### Mon, Oct 20` in the phone's locale. If the note already ends with that date's heading, the cursor moves there and nothing is added. The date comes from the core, tested. The editor only inserts the heading.
  *Built 2026-11-11:* the Date entry tool. For a class note the date comes from the core's `entry_date`; for any other note it is today. If the last dated heading is already that day's, written under or not, the cursor goes to the end and nothing is added.
- **C14a.** The after-class prompt's tap opens the class note on that meeting's dated entry, finishing what 042 C8 and C9 left waiting on Add entry.
  *Built 2026-11-11:* the after-class tap opens the class note with `entry`, which adds or finds that day's heading.

**Photos**
- **C15.** A note can hold photos from the camera or the library, shown in a strip below the text, each at most 1600 px on its long side. A photo has no position in the text, so it can't sit between two paragraphs.
  *Built 2026-11-14:* Photo in the tool sheet offers Camera or Library (`capture` with `saveTo` the app's `photo-tmp` folder); the plugin already writes at most 1600 px on the long side on both platforms, so no plugin change. `add_photo` takes the file into the `photos` table (bytes in the row) and deletes it. A strip of 64 px thumbnails sits under the text; a tap opens it full screen, and a long press or the viewer's Remove asks first.
- **C16.** Photos are kept apart from the note's text, so they never reach AI chunks or prompts. The app never sends them anywhere; the student can share or export them. They are rows in the store (the user, 2026-11-05), and no copy may claim more than that: they are encrypted and go wherever the store goes (on iOS the store isn't excluded from device or iCloud backups, so they're in those, encrypted, and count toward the student's iCloud space; Android has `allowBackup="false"`).
  *Built 2026-11-14:* `photos` is its own table, read by `note_photos` (no bytes) and `photo_bytes` (one at a time, raw bytes). Nothing in `sources()`, chunks or prompts reads it; a note with no text is not a source.
- **C17.** Deleting a note or erasing everything deletes its photos in one transaction. Sign-out keeps them, like notes. Share and Export carry them as a zip when a note has photos, and say so. That comes from the note's photo count, because nothing in the text marks them.
  *Built 2026-11-14:* `delete_note` removes the note, chunks and photos in one transaction; `wipe` clears `photos`, then VACUUMs; `forget_sis` leaves them. Share and Export of a note with photos (any note, for Export all) is a `.zip` (`notes_zip`, the `zip` crate, deflate only): `notes.md` and `photos/<note> <n>.jpg`; the sheet says photos go with it. A note with none stays a `.md`.
- **C17a.** Autosave doesn't save while the text is blank. Closing the editor with blank text deletes the note, so select-all and retype loses nothing, and if the app is killed mid-edit the old text comes back. A pin or subject goes with a deleted note. Sign-out closes the editor without saving, and the old text survives.
  *Built 2026-11-11:* `autosaves` and `onClose` in `md.ts`. Sign-out already closes the editor without saving.
- **C15a.** A note holds at most 20 photos, and adding a 21st says so. Adding a photo moves the note up its subject, like any edit.
  *Built 2026-11-14:* `add_photo` counts inside its transaction and returns `TooManyPhotos` ("A note holds up to 20 photos.") on the 21st; the sheet also refuses before opening the camera. Adding sets `updated`, so the note moves up. Test `c15a_21st_photo_refused`.
- **C17c.** *Photos phase.* A note can hold only photos, with no text. Adding a photo to a note with no row creates the row in the same transaction, with empty text and the held name and subject. A note with photos isn't deleted by blank text, from autosave or on close: the core checks this in one transaction, and its row stays, with the text and its AI chunks removed in the same call, so LAR can't cite erased words. Everything that reads a row as "has notes" counts this note as having notes only because of its photos, and the export skips its empty section. Delete asks first and removes the photos, in one transaction with the note, so a crash can't leave it half deleted.
  *Built 2026-11-14:* `add_photo` creates the row (empty text, held name) in its transaction, and the editor files the held subject after. `set_note` with blank text keeps a note that has photos, clears its text and drops its chunks in one transaction; `autosaves` and `onClose` take the photo count. Delete is `delete_note`, which asks first and names the photo count. Tests `c17c_first_photo_creates_the_row`, `c17c_blank_keeps_a_note_with_photos`, `c17c_kept_row_drops_its_chunks`.
- **C17d.** *Photos phase.* A note with photos and no text shows "3 photos" in lists. The Schedule dot and the class sheet count photos as notes. The after-class prompt (042 C8, C9) still needs text. Ask AI and Make cards on a note with no text say there's nothing to read, without calling the model.
  *Built 2026-11-14:* `Note.photos` carries the count; lists use `previewOf` ("3 photos"). The class sheet's "Class notes" counts the photo-only row; the Schedule grid has no notes dot to change. The after-class prompt already filters on text and still does. Ask LAR and Make cards on blank text answer "nothing in this note" before any model call. Tests `c17d_photo_only_preview`, `c17d_after_class_needs_text`.
- **C17b.** When a photo can't be taken or saved, one line says so and how to fix it (`cameraProblem()`), and the note is untouched.
  *Built 2026-11-14:* `photoProblem(cameraProblem(e))` gives one line each for denied, no camera, no space and other; the note is untouched. Not yet checked on a real camera.
  *Also built 2026-11-14:* the strip shows a ~256 px thumbnail made in the webview and stored beside the photo (`thumb`); the viewer loads the full JPEG only when opened. Photos are in the 047 backup (base64, restored in the same transaction as their notes), and the C11 Photos row counts real bytes. A backup over the 25 MB cap is not made: the app says "Your photos make this backup too big to restore here; it's N MB" (cap unchanged).

**Note to cards**
- **C18.** Make cards marks lines to choose from. Lines written `term - meaning` start chosen. No AI model is needed.
  *Built 2026-11-11:* Make cards (a tool, and in Ask LAR) lists the note's lines with boxes; `term - meaning` lines (also with – or —) start ticked, split into front and back.
- **C19.** A review step shows each card's front and back, editable, and which deck they go to: the subject's deck, or a new one named after the subject.
- **C20.** Nothing is saved until Save cards. Fronts the deck already has are dropped, using `tidy` in `assis/cards.ts`.
  *Built 2026-11-11:* the subject's deck if it has one, else a new deck named after the note, made once: a second Save adds to it. Save waits until the decks have loaded. `tidy` drops fronts the deck already has.
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
- Photos: a separate table of JPEG rows (`id, note_key, w, h, jpeg`), loaded only when shown. Per-student, Erase everything and atomic delete come from the store, with no new crypto, key or orphan sweep.
- Photo commands are async with `spawn_blocking` and return bytes through `tauri::ipc::Response`, because sync commands run on the main thread and a waiting one freezes the UI. Deleting a note is one transaction, bounded by C15a's cap: about 110 ms for 20 photos on a Mac, estimated 0.3-1 s on a low-cost phone. Larger jobs (zip export, 047's backup) take one photo per lock and release between; 500 in one statement took 2.7 s on the Mac. Lists never select `bytes` and read by an indexed `note_key`. Deleting doesn't shrink the file, and new photos reuse the space: Erase everything VACUUMs after clearing (22 ms when empty), and normal use never VACUUMs. `wipe` gets `DELETE FROM photos`; `forget_sis` leaves them.
- Ownership: `store.rs` and `lib.rs` belong to the Core role and are hot, so this goes to the Code engineer as an issue.
- Lifetime: subjects, pins and photos survive sign-out (`forget_sis` doesn't touch them), and Erase everything removes them (`store.wipe`).
- Entry date: `entry_date(sessions, marks, code, today)` in `notes.rs` or `today.rs` (030 C12).
- Commands: `src-tauri/src/lib.rs` is a hot file, so new commands go in one small PR.
- Camera: one plugin, shared with Scan (#197) and 047's QR, on `core/camera-plugin`, owned by the Head. `plugin:camera|capture` takes `{ source: "camera" | "library", read?: { text?, qr? }, saveTo? }` and returns `{ cancelled, path?, width?, height?, text?, qr? }`. It rejects with `camera_denied`, `no_camera`, `no_space`, `save_failed`, `bad_photo`, `bad_folder` or `busy`, and a cancel is not an error. Use `capture()` and `cameraProblem()` from `src/lib/camera.ts`.
- `saveTo` is an absolute folder inside the app's data directory. The plugin names the file and writes a JPEG of at most 1600 px on the long side, so downscaling happens there and not in the WebView. On iOS it sets `isExcludedFromBackup` and file protection.
- The plugin saves to a temp folder under the app's data directory (`tmp` and `Caches` are refused on iOS), and the core takes the file in and deletes it. A launch sweep and Erase everything clear that folder. The claim is "encrypted after a moment as a plain file", never "never on disk".
- `src/lib/api.ts`: `NoteItem` follows; `setNote` keeps its contract.
- Export: subject and pin stay out of the Markdown, which goes to classmates when shared. 047 C9's backup carries them.

## Errors

- Photo can't be taken or saved (any `cameraProblem()` code): the note keeps its text, a line says why and how to fix it.
- A saved note's photo is missing: a quiet placeholder with the file's name, and the rest of the note reads normally.
- Cards can't be saved: the review stays open with what was typed.

## Motion and Reduce Motion

A notebook pulled out changes the layout, so it opens over `--t-flow` (0.36 s) with the shared ease; a sheet rising uses the shared ease and spring, 0.3 s. What the notebook shows below it is simply there: nothing rises or spawns in after it. Checklist boxes and the `+N CARDS` stamp are eased too. Reduce Motion skips to the resting state. Haptics: `select` on a subject, `tick` on a checklist, `done` on Save cards.

## Accessibility

Every tool and row has a 44 pt target and a name. Checklist boxes are real controls with their state read out. Note text follows the iOS text size to the body cap. Subject colours are never the only way to tell subjects apart: the code is always written.

## Test map

| Criterion | Test |
|---|---|
| C2, C3, C4, C7 | `vitest`: `c4_subject_shelves_sort_pinned_then_newest` and siblings; `cargo`: note round trip with subject and pinned |
| C1b2, C1c, C1d, C1d2 | `vitest`: `c1b2_settles_and_wakes`, `c1c_no_cube_until_installed`, `c1d2_low_ram_never_starts_webgl`, `c1d2_a_still_neuron_never_starts_a_frame_loop`; real phone for the look |
| C1b | `vitest`: `c1b_page_padding_clears_the_chip` |
| C1d3 | `vitest`: `c1d3_the_same_seed_grows_the_same_neuron`, `c1d3_dendrites_stay_inside_the_glass_and_grow_from_him`, `c1d3_the_axon_reaches_every_source` and siblings in `neuron.test.ts`; simulator for the flight and the fire |
| C6 | `vitest`: `c6_search_across_subjects` |
| C1 | `vitest`: `c1_cards_group_decks_by_subject_in_shelf_order`, `c1_deck_bar_is_a_pixel_per_3_cards_gold_for_due`, `c1_done_bars_are_the_last_seven_days_ending_today`; `cargo test`: `week_counts_each_local_day_with_gaps_as_zero`; screenshot, real phone for the tiles and the slide |
| C10 | `vitest`: `c10_markdown_round_trip` (`editor/md.test.ts`) |
| C11, C12 | `vitest`: `c11_wraps_and_unwraps_a_selection`, `c11_turns_lines_into_a_list_and_back`, `c11_a_code_block_puts_the_cursor_inside`, `c12_a_tick_flips_only_that_box`; simulator for the formatting and ticks |
| C13, C14 | `vitest`: `c13_template_never_replaces`, `c14_entry_not_repeated`, `c14_heading_in_the_phones_locale`; `cargo`: `c14_entry_date_skips_vacant_follows_moved`, `c14_no_future_meeting_uses_today` |
| C14a | `vitest`: `c14a_after_class_opens_the_entry` |
| C12a | `vitest`: `c12a_lar_text_survives_autosave` |
| C17a | `vitest`: `c17a_blank_never_autosaves`, `c17a_blank_on_close_deletes` |
| C15a | `cargo`: `c15a_21st_photo_refused` |
| C17c | `cargo`: `c17c_kept_row_drops_its_chunks`, `c17c_blank_keeps_a_note_with_photos`, `c17c_first_photo_creates_the_row`, next to `c8_delete_note_drops_chunks`; Delete removes the photos |
| C17d | `vitest`: `c17d_photo_only_preview`, `c17d_after_class_needs_text`; `cargo`: empty `notes_markdown` section |
| Data | `cargo`: `old_schema_opens_and_gains_columns`, `migration_error_is_not_locked`, `pin_and_subject_keep_updated`, `meta_on_missing_key_errors`, `subject_refused_on_class_and_day`, `preview_strips_checklist_and_highlight` |
| C16, C17 | `cargo`: `c17_note_delete_removes_photos`, per-student store |
| C18–C20 | `vitest`: `c18_term_lines_start_chosen`, `c20_duplicates_dropped` |
| C9, C11, C12, C15, C22 | screenshot, real phone |
| C11a | real phone: keep awake holds while writing, and again after leaving the app and coming back |

## Open questions

- "Add fonts for the cube": the user asked for this and it isn't clear what it means. Nothing is built for it.
- Mathematics and tables in notes: offered, not requested.
- Strip or between paragraphs: the picks page shows a strip, which keeps the text clean for AI, and that's what gets built. A photo beside a specific paragraph would need references in the text.
- C15a's cap of 20 is a proposal, sized by the delete timing measured on a Mac (0.5 MB photo: insert 17-19 ms, read 2-4 ms, delete 25-34 ms). Measure on a low-cost Android in the photos phase.
