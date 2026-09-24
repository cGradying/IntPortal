# 01 — Foundation and shell

Status: approved design (prototype v2). Build first; every other spec depends on it.

## Reference
- Prototype: `docs/specs/prototypes/intportal-v2.html` — `.window`, `.side`, `.head`, `.sheet`.
- Design system: `DESIGN.md`.

## Current behaviour inventory (must keep)
- ⌘1 Schedule, ⌘2 Today/Notebook, ⌘3 Grades, ⌘0 Home, ⌘[ / ⌘] previous/next, ⌘N new event
  (Schedule), ⌘+ / ⌘- / ⌥⌘0 zoom, ⌘, Settings, Account menu ⌘R Refresh / Edit Credentials / Sign
  Out — `App/PUPSISPortalApp.swift` commands.
- UI Scale (`\.uiScale`) multiplies every type size.
- `ScheduleModel` / `NotebookModel` intents (`stepIntent`, `newEventIntent`) drive screen actions.
- Menu bar extra, notifications, window drag area, traffic-light auto-hide.
- Reduce Motion honored everywhere (`Motion.* (reduced:)` returns nil).

## UX changes
1. **Sidebar takes over navigation from the nav island.** `NavIsland.swift`, `HomeNoiseField.swift`
   and the home launcher are deleted. The island itself returns as chrome for the glance and the
   screen's controls (spec 12, decided 2026-09-24). The sidebar lists Today, Schedule, Grades / Notebook, Quizzes, Syllabus /
   Settings. Settings becomes a screen (it was a sheet).
2. **Today is its own screen.** The agenda leaves Notebook (spec 04).
3. **Notebook's tabs (Vault / Quizzes / Syllabus) become sidebar entries.** `NotebookModel.tab`
   retires.
4. **⌘0 opens the portal hub** (spec 09) instead of the home launcher. New shortcuts: ⌘4 Notebook,
   ⌘5 Quizzes, ⌘6 Syllabus; ⌘2 becomes Today.
5. **Per-screen controls live in the island** (spec 12): Schedule's view picker, week nav, Today,
   New event and Refresh open out of the island on hover.
6. **Header**: screen title (display 28), one-line context, breadcrumb "Student Module › Screen".
   No controls row.

## Layout & components

### New files
- `Core/Theme.swift`: extend `Palette` with the role set in `DESIGN.md` — `menuField`,
  `menuFieldDeep`, `menuFieldHover`, `onMenu`, `onMenu2`, `action`, `actionHover`, `actionSoft`,
  `actionInk`, `gold`, `goldInk`, `goldSoft`, `ground`, `sheet`, `sunk`, `line`, `line2`, `ink`,
  `ink2`, `ink3`, `good`, `bad`. Add `Palette.registrar` and `Palette.registrarNight`; `.auto` maps
  to them. Keep `color(for:)` and the character-sum seed.
- `Core/Theme.swift`: add `enum Spacing { xs 4, sm 8, md 12, lg 16, xl 20, xxl 28 }` (today only
  in DESIGN.md frontmatter).
- `Core/Theme.swift`: `Typography` gains `display(size:weight:)` (Pixelify Sans) and routes every
  existing role per the table in `DESIGN.md`. `FontChoice` now applies to body roles only.
- `Resources/Fonts/PixelifySans/`, `Resources/Fonts/SourceSans3/` (OFL, variable) +
  `FontLibrary` registration. Add `OFL.txt` for each.
- `Views/Pixel/PixelNotch.swift`: `InsettableShape` with 2pt+2pt stepped corners (8-point
  polygon per corner). Replaces every content `RoundedRectangle`.
- `Views/Pixel/PixelIcon.swift`: `PixelIcon(.today)` renders a 12×12 bitmap with `Canvas`
  (`fillRect` per on-cell), sizes 12 / 24 only. Bitmaps live in `PixelIcon.Glyph` (copy the strings
  from the prototype's `ICONS`). Reuse the bitmap drawing already in `Views/Quiz/QuizVisuals.swift`
  (`PixelBadge`) — move it here and make `PixelBadge` a caller.
- `Views/Pixel/Sheet.swift`: `Sheet(label:meta:) { content }` — notch, 1pt line, header strip.
- `Views/Pixel/PixelButtonStyle.swift`: `.pixelPrimary`, `.pixelSecondary`, `.pixelSmall`
  (display face, notch, inset focus ring).
- `Views/Pixel/Stamp.swift`: `Stamp(.online)`; ink mask = a 90×90 noise image generated once with
  `Canvas` and cached; `thunk` via `Motion.thunk(reduced:)`.
- `Views/Shell/Sidebar.swift`, `Views/Shell/ScreenHeader.swift`, `Views/Shell/PortalGlyph.swift`
  (13×18 swirl drawn in `Canvas` inside `TimelineView(.periodic(from:.now, by:0.11))`, paused under
  Reduce Motion or when the window is inactive).
- `Core/Theme.swift` `Motion`: add `thunk`, `flip`, `pop`, `portalForm`, `ignite`, `warp`,
  `sweep`; `island` returns for the island (spec 12).

### Changed
- `App/PUPSISPortalApp.swift` `ContentView`: `ZStack { AppShell; if landing { PortalLanding } }`.
  `AppShell` = `HStack(spacing: 0) { Sidebar.frame(width: 236); VStack { ScreenHeader; screen } }`.
  `Destination` gains `.today, .notebook, .quizzes, .syllabus, .settings`.
- Commands: update ⌘ mapping above; ⌘0 → `appState.showHub()`.
- `Views/GlassCompat.swift`: callers removed from content; keep the file only while any system
  control still uses it, then delete.
- Any Liquid Glass agent guidance (the `liquid-glass` skill from PUPSISPortal) no longer applies
  to app content.

### Deleted
`NavIsland.swift`, `HomeNoiseField.swift`, `DitherFill.swift`'s top-band use (keep the Bayer helper,
it moves to `Views/Pixel/Dither.swift`), `WindowChrome.swift` drag band if the sidebar provides the
drag area.

## States
- Signed out: shell hidden, landing in sign-in phase (spec 09).
- Stale cache: sidebar sync line reads "sis8 · updated 3 h ago" in `on-maroon-2`.
- Refresh failing: sync dot turns `bad`, line reads "Couldn't reach SIS · Try again".
- Update available: sidebar footer shows "vX available" (keep `UpdateCheck` badge).

## Accessibility & motion
- Sidebar items are buttons with `accessibilityAddTraits(.isSelected)` on the current one.
- Every icon-only control has a label (critique finding: the notes toolbar had none).
- Focus ring = inset 2pt action color (outer rings are clipped by the notch).
- Min text size 11pt at UI Scale 100%.

## 3D
Screen changes use `DepthPush` (`Views/Depth/DepthPush.swift`, token `depthPush`) along the sidebar's order: forward going down the menu, back going up. Refresh plays `SyncRipple` from `PortalGlyph` (token `ripple`), green on success, red stutter on failure.

## Acceptance criteria
- [ ] Changing screens moves forward or back in Z by sidebar order; Reduce Motion (system or in-app) removes it. Evidence: `DestinationTests` + screenshots.
- [ ] ⌘R plays one ripple from the glyph; a failed refresh plays the red stutter and the glyph line reads "Couldn't reach SIS · Try again". Evidence: screenshots in demo mode.
- [ ] Every screen reachable from the sidebar and by ⌘1–6, ⌘, ; ⌘0 opens the hub. Evidence: manual.
- [ ] No `RoundedRectangle`, `glassEffect`, or hex literal in `Views/` (except `Pixel/` bitmaps).
      Evidence: `grep`.
- [ ] Registrar and Registrar Night match the prototype's tokens within rounding. Evidence:
      screenshots side by side.
- [ ] UI Scale 80% / 100% / 140% keeps the sidebar and header intact. Evidence: screenshots.
- [ ] Reduce Motion: no transitions, glyph static. Evidence: manual with the system toggle.
- [ ] `swift test` passes; `PixelNotch` path test (corner points) and `Typography` role test
      updated.

## Seams
No Core logic changes. `AppState`, `PortalController`, `Preferences` APIs unchanged except new
theme cases and the destination enum.

## Out of scope
Windows port. iOS.
