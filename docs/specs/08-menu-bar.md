# 08 — Menu bar

Status: light restyle only.

## Current behaviour inventory (must keep)
`Views/MenuBarPanel.swift`: label `CODE · 12m` / `CODE · 3:00 PM`; panel "Up next", "Later today"
(with "now"), "Tomorrow · CODE at …", "Reminders on · N min before" / "Reminders off", "Sign in to
see your schedule.", "No more classes this week."

## UX changes
- Label unchanged (menu bar text must stay system-rendered).
- Panel: sheet styling (notch, sunk rows), code in display face with subject color, stamps for
  online/vacant, gold "now" marker, campus chip in the footer, "Open IntPortal" button.
- No glass.

## Acceptance criteria
- [ ] Same content and states as today. Evidence: `DayAgendaTests` + screenshots.
