# 04 — Today and Notebook

Status: approved design (prototype v2). Today becomes its own screen; Notebook is the vault + editor.

## Reference
Prototype `intportal-v2.html`: `#s-today`, `renderToday()`, `gapRow()`; `#s-notebook`, `openAsk()`.

## Current behaviour inventory (must keep)
From `Views/AgendaView.swift`, `Core/DayAgenda.swift`, `Core/NotesStore.swift`,
`Views/WebNoteEditor.swift`, `notes-editor/src/editor.js`:
- Today timeline: classes and calendar events with "In session", countdown, "Done", "Now", online
  video icon, faded past rows, "Xh free" gaps ≥ 15 min, "Tomorrow · CODE at 9:00" /
  "Tomorrow · nothing scheduled", "Nothing scheduled today.", day-syllabus markers.
- Day note navigator (prev/next, date picker, dot when the note has content).
- Vault: nested folders, drag to move, context menu (New note / New folder / Rename / Label colour /
  Include in AI search / Copy text / Export Markdown·Plain text·PDF / Delete with confirmation),
  "N of M notes in AI search — click to show which", "All notes" history, note types day/class/
  event/vault, title override, empty state.
- Editor: tabs (closeable, drop to open), Title field, CodeMirror live preview, KaTeX `$…$`/`$$…$$`,
  full LaTeX documents, fenced code + Copy, checkboxes, `[[wikilinks]]`, images (paste/drop/URL),
  highlight and text colour, database tables (typed columns, status tags), reading width 420–1100,
  sidebar side (Settings ▸ Layout), "Add dated entry" for class notes, Ask AI pill (spec 06).

## UX changes
### Today (new screen, ⌘2)
- Two columns: **Your day** sheet (timeline) | rail: **This term** (Subjects enrolled, Units, Cards
  due today, Study streak) and **Due soon** (date tiles from syllabi; exams show days left in `bad`).
- Timeline rows: time column in display face; class code in subject color; tag (Done / in 3h 50m /
  In session); stamp for the class's status.
- Free rows: sunk background, "Free · 6h" + dithered gold bar; the gold **Now** line sits inside the
  free row it falls in; **Study in the gap** suggestion inside (spec 11).
- Day notes and the day navigator move to Notebook (a "Today's note" entry at the top of the vault).

### Notebook (⌘4)
- Two columns: vault sheet (214pt, resizable 200–480) | editor sheet.
- Vault header: "Vault" label + "5 of 6 in AI search" toggle (shows per-row sparkle marks,
  dimmed when excluded). Folder heads in display caps. Current note = action-soft row.
- Editor sheet: kicker "COMP 001 · class note" in subject color, title in display 27, meta line,
  body in Source Sans 3 15/1.45, max 66ch.
- **Formatting toolbar stays in the floating deck** (decided 2026-09-24; the deck is the student's
  own chrome). Spec 06 restyles it in pixel and groups it (Text: heading, bold, italic, strike,
  highlight, colour · Blocks: code, math, LaTeX, lists, checklist, quote, divider, table · Insert:
  image, link, note link), each with a label/tooltip and accessibility label. Critique fix for the
  18 unlabeled icons.
- `notes-editor/src/editor.css`: map CSS variables to the new tokens (sheet, ink, line, action,
  gold); headings h1–h3 in Pixelify Sans; body Source Sans 3; code keeps its mono; selection =
  gold-soft. Pass tokens from Swift through `PUPNotes.setTheme({…})` (new bridge call) so dark mode
  and theme rooms apply.
- Empty editor state (critique): "Pick a note or start one" + New note.
- Vault shows note titles, never raw AI prompts (critique: prompts as filenames) — use the note's
  first heading or the title override.

## States
No notes: empty vault state. Note excluded from AI search: dimmed sparkle + tooltip. Editor
loading: sheet skeleton lines (no spinner).

## Accessibility & motion
Timeline rows read "COMP 002 lecture, 9 to 12, done". Toolbar buttons all labelled. Reduce
Motion: no Ask AI sweep (text appears).

## Acceptance criteria
- [ ] Every inventory item still works. Evidence: manual pass + `DayAgendaTests`, `NotesStoreTests`.
- [ ] Toolbar buttons have labels (VoiceOver rotor). Evidence: Accessibility Inspector.
- [ ] Editor follows light/dark and theme rooms via `setTheme`. Evidence: screenshots.
- [ ] Today screen matches the prototype layout. Evidence: screenshot pair.

## Seams
`DayAgenda.timeline`, `remainingFreeMinutes`, `NotesStore`, `WebNoteBridge` (+ `setTheme`),
`GapSuggestion` (spec 11).
