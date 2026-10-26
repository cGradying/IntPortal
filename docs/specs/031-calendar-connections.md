# 031 Calendar connections and custom calendars

**Status:** draft, wording to confirm

## What changes for the student

The student picks which of their phone's calendars (Google, iCloud, Outlook, school) show beside their classes, each in its own colour, in both Day and Week view. They can make their own IntPortal calendars, such as "Org" or "Part-time", add events to them, and LAR can add an extra class session there after a confirm. Calendars from other accounts stay read-only.

## Direction and references

- The original Mac app: Settings → Calendar → Connect…, a ticked list of calendars with colour dot and account, events drawn on the same grid as classes, its own classes filtered out so they do not show twice (`docs/legacy/FEATURES.md` around line 467; `IntPortal/Sources/PUPSISPortalApp/Core/CalendarBridge.swift`, `Views/SettingsView.swift`, `Views/CalendarView.swift`).
- On a phone, "other calendars" already means every account added in the phone's settings: Google, iCloud, Outlook and Exchange, plus any ICS feed the student subscribed to there. The app reads them through EventKit (iOS) and CalendarContract (Android); no Google sign-in inside the app.
- This spec replaces spec 030's parity rows for "other calendars on the grid" (Partial) and "creating events" (Won't port) for the phone.

## Keep

- "Keep classes in my calendar": the IntPortal calendar of classes, written by `sync_classes` (`plugins/tauri-plugin-calendar`).
- The `.ics` share of classes (`crates/intportal-core/src/calendar.rs`).
- Busy time on Today and the coach counting the student's events (`crates/intportal-core/src/today.rs`).
- The student's own calendars are never changed by the app.

## Behaviour

- **C1.** You → Calendar shows "Calendars on this phone": one row per calendar with its colour dot, name and account, each with a switch. All are off until the student turns them on. This replaces the single "Show my own events" switch; a student who had it on starts with every calendar on.
- **C2.** Events from the switched-on calendars appear in Week view and in Day view (Day view shows none today), in their calendar's colour, beside classes on the same grid; overlaps lay out side by side.
- **C3.** All-day events sit in a strip at the top of the day, not as busy time.
- **C4.** The app's own class events never appear twice: events in the IntPortal classes calendar are left out of C2.
- **C5.** "My calendars" lists the IntPortal calendars. The student can add one with a name (up to 30 characters) and one of 8 colours, rename it, change its colour, or delete it after a confirm that says how many events it holds.
- **C6.** Each IntPortal calendar is a real calendar on the phone (an EventKit calendar on iOS, a local CalendarContract calendar on Android), so the events also show in the phone's own calendar app.
- **C7.** "Add event" in Day and Week view opens the phone's own event editor (EKEventEditViewController on iOS, `ACTION_INSERT` on Android) with the chosen IntPortal calendar and the tapped time filled in. Tapping an event opens it in the phone's viewer or editor.
- **C8.** The class sync stops wiping the whole IntPortal classes calendar: it deletes and rewrites only its own keyed class events, so nothing else the student or LAR put there is lost.
- **C9.** LAR's "add an extra session" (spec 023 C11) writes one event into the student's chosen IntPortal calendar after Apply; Undo deletes exactly that event.
- **C10.** The app and LAR never write to, change or delete events in calendars from other accounts.
- **C11.** Without full calendar access the list in C1 shows one row, "Allow calendar access to see your other calendars", which asks; iOS write-only access is explained in one line: "IntPortal can add classes, but needs full access to show your other calendars."
- **C12.** Turning a calendar off removes its events from the grid at once; nothing is stored by IntPortal beyond the list of switched-on calendar ids.

## Copy

- Section titles: "Calendars on this phone", "My calendars".
- Add: "New calendar", "Name", "Colour", "Create".
- Delete confirm: "Delete \"Org\" and its 12 events? This also removes them from your phone's calendar." Buttons: "Delete", "Keep".
- Read-only note under C1: "IntPortal only reads these. It never changes them."
- iOS privacy text (`NSCalendarsFullAccessUsageDescription`): "IntPortal shows your other calendars beside your classes and keeps your classes and your IntPortal calendars up to date. It never changes your other calendars."

## Data shape

- `plugins/tauri-plugin-calendar` (iOS Swift and Android Kotlin):
  - new `calendars` returning `{id, title, colour, account, writable, own}`;
  - `events` takes `calendarIds` and returns `{id, calendarId, title, start, end, allDay, colour}`;
  - new `create_calendar(name, colour)`, `update_calendar(id, name, colour)`, `delete_calendar(id)` for IntPortal calendars only;
  - new `add_event(calendarId, title, start, end, location?)` returning the event id, and `delete_event(id)` for IntPortal calendars only (for LAR's Apply and Undo);
  - new `open_event(id?)` showing the system viewer or editor;
  - `sync_classes` deletes by key, not by date range.
- UI state: the switched-on calendar ids and the default IntPortal calendar id, in the same place as today's calendar flags (`src/lib/state.svelte.ts`).
- Core: nothing new; the phone's calendar is the store.

## Errors

- Access denied: the C11 row; nothing else changes.
- A calendar was deleted outside the app: it disappears from the lists on next open.
- Writing fails: "Couldn't add that to your calendar. Check calendar access in Settings."

## Motion and Reduce Motion

No new motion.

## Accessibility

Each calendar row reads "Org, IntPortal calendar, shown" or "Work, Google, hidden". Colour is never the only cue: Day and Week events show the calendar name in VoiceOver and TalkBack labels.

## Out of scope

- An ICS link subscription inside the app (the phone's own settings already subscribe, and C1 then shows it).
- Google sign-in or any server.
- Drag to create or move events on the grid.
- Editing events in calendars from other accounts.

## Test map

| Criterion | Check |
|---|---|
| C1, C5, C11, C12 | vitest with the plugin mocked; screenshot on the UI simulator |
| C2–C4, C7 | screenshot on iOS simulator and Android emulator with a seeded calendar |
| C6, C8–C10 | plugin checks on device: `adb shell content query --uri content://com.android.calendar/calendars` and events after a class sync; iOS manual check in the Calendar app |

## Open questions

1. Should the student's IntPortal calendars sync to iCloud (the default calendar's account on iOS) or stay on the phone only like Android's local account?
2. Should spec 041's one deadline list read events from these calendars too?
3. Who owns which part: plugins (Android and iOS roles), You and Schedule screens (UI), LAR's Apply (AI)?
