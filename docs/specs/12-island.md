# 12 — Island

Status: decided 2026-09-24 (wayfinder map "Custom environment in the new UI"). Layout waits on
the HTML prototype review (prototype v3, artifact v5).

## Reference
The student's own NavIsland at `fa3c6ac` (`Views/NavIsland.swift`), and the prototype's island
once IP lands.

## Current behaviour inventory (from NavIsland at `fa3c6ac`)
- A pill that starts centred as a home launcher (date, glance line, destination tabs, gear), then
  flies to the top when a screen opens.
- Idle at the top: a compact pill with the screen's symbol and title plus a glance ("COMP 002 in
  12m", or the weekday when nothing is coming).
- On hover it morphs into the full bar: home, destination tabs, the screen's controls (Schedule:
  scale picker, previous, Today, next, show cancelled, new event; Notebook: the tab picker) and a
  gear. "Expand island on hover" off keeps it expanded.
- "Open on the home launcher" chose whether launch lands on the launcher.
- Every icon-only control has an accessibility label.

## UX changes
1. The island returns **beside the sidebar**, floating at the top centre of the content column.
   Navigation stays in the sidebar; the island carries the glance and the screen's controls.
2. **Glance priority:** the class in session ("COMP 002 · until 10:50" + its stamp), the next
   class today ("COMP 002 · in 12m"), sync trouble ("Couldn't reach SIS · Try again"), IntAssis
   thinking (the voxel cube), else "No more classes today · Tomorrow COMP 001 at 9:00".
3. **Hover opens the screen's controls.** Schedule hosts `ScheduleControls` (SC1). Other screens'
   controls come from the prototype review. The header keeps only the title and context.
4. **Settings › General › Island:** "Show the island", "Expand on hover". The home launcher is
   the hub now, so "Open on" (Hub or Today) replaces "Open on the home launcher".
5. Pixel, not glass: notched pill in `roles.menuFieldDeep` with `onMenu` text; the row is a window
   drag area.

## States
Signed out or on the landing: no island. Syncing: the glance keeps its line; the sidebar glyph
spins. Reduce Motion: no morph, the controls swap in place.

## Accessibility & motion
The glance is a live region (announced when it changes class). Controls keep their labels.
Motion token `island` (spring, response 0.28, damping 0.9, interruptible).

## Acceptance criteria
- [ ] `IslandGlanceTests` pin all five glance cases with literal strings.
- [ ] Hover expands and collapses; "Expand on hover" off keeps it open. Evidence: live capture.
- [ ] The window drags by the island row. Evidence: live check.

## Seams
`DayAgenda.timeline`, `NextClass`, `ShellSidebar.sync(...)`, `AssistantSession.isBusy`,
`Preferences.showIsland` / `islandExpandOnHover` / `launchDestination`.
