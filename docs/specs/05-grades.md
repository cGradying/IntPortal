# 05 — Grades

Status: approved design (prototype v2).

## Reference
Prototype `intportal-v2.html`: `#s-grades`, `renderGrades()`.

## Current behaviour inventory (must keep)
From `Views/GradesView.swift`: "GPA" to two decimals, "N of M subjects posted" / "No grades posted
yet", "GPA trend" (inverted axis, VoiceOver summary "up from / down from"), "Units completed X /
total" or "Set your program's total units in Settings to see progress.", "What do I need" target
calculator ("lower is better on PUP's 1.00–5.00 scale"), "Term" picker, "Load past terms" /
"Loading past terms…", "Pending" for ungraded, "No grades yet", "Updated …" + Refresh / Try again.

## UX changes
- Layout: two sheets on top — **Term** (School year + Semester selects, as on the SIS grades page,
  then the GPA hero: display 56 + "GPA, 5 of 5 subjects posted, 14 units." + "All passed" pill) |
  **GPA trend** (pixel chart: square markers, dashed 1.00/1.50/2.00 guides, last point filled and
  labelled) — then the **Grades** table sheet (Subject, Description, Units, Final grade in display,
  Remarks pill; GPA footer).
- Units completed and What do I need move into a third sheet under the table.
- Empty term: dithered empty state "No grades yet" + the posted-term shortcut.
- Wording: **GPA** everywhere (never GWA).

## Acceptance criteria
- [ ] All inventory items work, including backfill. Evidence: manual + `GradesParserTests`.
- [ ] Chart is readable in both themes and has the VoiceOver summary. Evidence: Accessibility
      Inspector.

## Seams
`PortalController.grades`, `gradeHistory`, `loadGradeHistory()`, `GradesStore`. Backend W1d
(backfill keeps partial terms) should land first.
