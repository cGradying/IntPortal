# 07 — Settings

Status: approved design (prototype v2 shows Intelligence + Account; the other panes follow the same
sheet pattern).

## Current behaviour inventory (must keep)
`Views/SettingsView.swift` (1,617 lines), 8 panes, each with "Reset This Pane to Defaults" and
"Technical Details":
General (Dynamic Island options, Force Reduce Motion, Notes Database Reveal, Delete All Notes…,
Reset All Settings…) · Appearance (Theme, Font, UI Scale + Reset to 100%, Notes sidebar side,
Subject Colors) · Schedule (Calendar.app connect/calendars/in-person & online targets/Repeat
until/Add to Calendar…/Open Internet Accounts…/Export .ics…, Google Calendar direct, Program total
units) · Notifications (Remind me before class, How early, Open System Settings…) · Intelligence
(IntAssis, Model source Local/OpenAI/Google/Anthropic, Model, API key + Keychain note, Permission,
Text reveal, Edit IntAssis instructions…, Thinking, Context size + RAM indicator, Models catalog
Download/Use/Selected, low-memory alert, Advanced AI Tuning, AI Tuning) · Storage (Total on disk,
Reveal, delete models) · Account (Last updated, Refresh Schedule, Edit Credentials, Sign Out, SIS
endpoint) · About (Check for Updates…, automatic updates, author, contact, Donate "Coming soon",
Terms of Use).

## UX changes
1. Settings is a **screen** in the sidebar (⌘,), not a sheet. Pane list = left segmented column
   inside the screen; each pane = one or two sheets of rows (label left, control right).
2. **General:** "Dynamic Island" group removed (island is gone). New: **"Play portal intro"**
   (default on) and keep "Start at login", "Auto-hide window buttons".
3. **Appearance:** Theme = Auto (Registrar / Registrar Night) + the rooms that fill the new role set
   (see DESIGN.md › Theme rooms). Font applies to body text only (display is fixed).
4. **Account:** + **Campus** picker (spec 10), + **SIS server** "Automatic (sis8)" / fixed host
   (spec 00), + "Back to the portal hub".
5. **Intelligence:** same controls; footer copy fixed (W10); cloud note "Stored in your Keychain,
   sent only to {provider}'s own API. Note search and quiz generation still run on this Mac."
6. Split `SettingsView.swift` into one file per pane under `Views/Settings/`.

## Acceptance criteria
- [ ] Every setting above still reads/writes the same `Preferences` key. Evidence: `PreferencesTests`.
- [ ] Each pane file < 350 lines. Evidence: `wc -l`.
- [ ] Reset This Pane still works per pane. Evidence: manual.

## Seams
`Preferences` (+ `playPortalIntro`, `campusOverride`, `sisHostOverride`), `ModelCatalog`,
`KeychainStore`, `UpdaterBridge`.
