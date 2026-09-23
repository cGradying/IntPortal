import Foundation

/// Everything needed to recreate an event, as plain values. Undo works on
/// these rather than on `EKEvent`, which stops being valid the moment the
/// store is reset or the week reloads.
struct EventSnapshot: Equatable {
    var title: String
    var calendarID: String
    /// The day the occurrence sits on.
    var date: Date
    var start: Int
    var end: Int
    /// The weekdays this covers. Without `repeatsWeekly` they're one-off
    /// events on each of those days, not a series.
    var repeatDays: [Weekday]
    /// Off by default: a drag across three days should give three blocks this
    /// week, not something that comes back every week until the term ends.
    var repeatsWeekly = false
    /// Both optional, both map straight to `EKEvent.notes`/`.url` — nothing
    /// app-specific, so Calendar.app and any other client show them too.
    var note = ""
    var link = ""
    var location = ""
    /// `EKAlarm.relativeOffset` values (seconds before the start, so
    /// negative). Absolute-date alarms aren't captured — rare on a
    /// class/study event, and the offset is what needs to travel with a
    /// moved or recreated occurrence, not a fixed clock time.
    var alarmOffsets: [TimeInterval] = []

    var isMultiDay: Bool { repeatDays.count > 1 }

    var timeLabel: String {
        "\(ClassSession.format(start)) – \(ClassSession.format(end))"
    }

    /// `Mon, Wed, Fri · 2:00PM – 4:00PM`, or a single date when it doesn't
    /// repeat.
    var summary: String {
        let when = isMultiDay
            ? repeatDays.map(\.short).map { $0.capitalized }.joined(separator: ", ")
            : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let every = repeatsWeekly ? "every " : ""
        return "\(every)\(when) · \(timeLabel)"
    }

    /// The date each covered weekday falls on, for creating one-off events
    /// across a multi-day drag.
    func dates(inWeekStarting weekStart: Date) -> [Date] {
        repeatDays.map { $0.date(inWeekStarting: weekStart) }
    }
}

/// The one door every calendar mutation goes through, so undo has a single
/// place to hook and views never touch `CalendarBridge` directly for writes.
@MainActor
final class EventEditor: ObservableObject {
    private let bridge: CalendarBridge
    /// Set from the view hierarchy so ⌘Z and ⇧⌘Z come from the standard Edit
    /// menu rather than a hand-rolled stack.
    var undoManager: UndoManager?
    /// Called after any change so the week can be re-read.
    var onChange: (() -> Void)?

    init(bridge: CalendarBridge) {
        self.bridge = bridge
    }

    // MARK: Operations

    /// Repeating gives one event with a weekly rule across the chosen days.
    /// Not repeating gives one plain event per day — the days were still
    /// selected, they just don't come back next week.
    func create(_ snapshot: EventSnapshot, inWeekStarting weekStart: Date, actionName: String = "Add Event") {
        let notes = snapshot.note.isEmpty ? nil : snapshot.note
        let url = URL(string: snapshot.link)
        let location = snapshot.location.isEmpty ? nil : snapshot.location
        if snapshot.repeatsWeekly {
            guard bridge.add(
                title: snapshot.title,
                on: snapshot.date,
                start: snapshot.start,
                end: snapshot.end,
                repeatingOn: snapshot.repeatDays,
                until: termEnd,
                calendarID: snapshot.calendarID,
                notes: notes,
                url: url,
                location: location,
                alarmOffsets: snapshot.alarmOffsets
            ) != nil else { return }
        } else {
            for date in snapshot.dates(inWeekStarting: weekStart) {
                _ = bridge.add(
                    title: snapshot.title,
                    on: date,
                    start: snapshot.start,
                    end: snapshot.end,
                    calendarID: snapshot.calendarID,
                    notes: notes,
                    url: url,
                    location: location,
                    alarmOffsets: snapshot.alarmOffsets
                )
            }
        }

        register(actionName) { editor in
            editor.deleteAll(matching: snapshot, inWeekStarting: weekStart, actionName: actionName)
        }
        onChange?()
    }

    func delete(
        _ block: DayBlock,
        scope: CalendarBridge.EditScope,
        inWeekStarting weekStart: Date,
        actionName: String = "Delete Event"
    ) {
        guard let snapshot = snapshot(of: block) else { return }

        bridge.delete(block, scope: scope)
        // A snapshot only ever describes the one occurrence that was edited,
        // never the whole series. For a genuine one-off that's the entire
        // event, so recreating it is exact. For a repeating event it's not —
        // recreating a fresh series from one occurrence's snapshot would
        // duplicate whatever `.thisEvent`/`.futureEvents` left behind, and
        // still lose the exceptions on the occurrences that survived. No
        // undo beats a wrong one.
        if Self.canUndoDelete(of: snapshot) {
            register(actionName) { editor in
                editor.create(snapshot, inWeekStarting: weekStart, actionName: actionName)
            }
        }
        onChange?()
    }

    /// Pure so the "don't offer undo for a repeating delete" rule is
    /// directly testable without a live `EKEventStore`.
    nonisolated static func canUndoDelete(of snapshot: EventSnapshot) -> Bool {
        !snapshot.repeatsWeekly
    }

    func move(
        _ block: DayBlock,
        to date: Date,
        start: Int,
        end: Int,
        scope: CalendarBridge.EditScope,
        actionName: String = "Move Event"
    ) {
        guard let before = snapshot(of: block) else { return }
        let title = block.title
        let destinationDay = Weekday.on(date)

        // Captured from the bridge's return value, *after* the save — not
        // before. Saving one occurrence of a repeating event with
        // `.thisEvent` (or forking it with `.futureEvents`) can detach it
        // under a brand new identifier; a pre-save read would already be
        // stale by the time undo needs it. `?? ""` matches nothing in
        // `findOccurrence`'s identifier pass, which is exactly the "fall
        // back to day/time/title" behavior wanted here.
        let identifier = bridge.reschedule(block, to: date, start: start, end: end, scope: scope) ?? ""
        register(actionName) { editor in
            // The block is stale after a reload, so undo goes back through the
            // freshly-loaded occurrence at the moved-to slot — not just any
            // same-title event in the week, which could be a different
            // occurrence of the same series or an unrelated event that
            // happens to share a name.
            editor.moveBack(
                to: before,
                identifier: identifier,
                day: destinationDay,
                start: start,
                end: end,
                title: title,
                scope: scope,
                actionName: actionName
            )
        }
        onChange?()
    }

    func rename(_ block: DayBlock, to title: String, scope: CalendarBridge.EditScope) {
        guard let before = snapshot(of: block) else { return }
        let day = block.day

        // Post-save, not pre-save — see `move`'s comment; the same
        // identifier drift can happen renaming a single occurrence too.
        let identifier = bridge.rename(block, to: title, scope: scope) ?? ""
        register("Rename Event") { editor in
            // `title` (the new one), not `before.title` — that's what the
            // block looks like right now, which is what undo needs to find.
            editor.renameBack(to: before, identifier: identifier, day: day, currentTitle: title, scope: scope)
        }
        onChange?()
    }

    func setDetails(_ block: DayBlock, note: String, link: String, scope: CalendarBridge.EditScope) {
        guard let before = snapshot(of: block) else { return }
        let day = block.day
        let title = block.title

        let identifier = bridge.setDetails(block, note: note, link: link, scope: scope) ?? ""
        register("Edit Event Details") { editor in
            editor.setDetailsBack(to: before, identifier: identifier, day: day, title: title, scope: scope)
        }
        onChange?()
    }

    func duplicate(_ block: DayBlock, inWeekStarting weekStart: Date) {
        guard var snapshot = snapshot(of: block) else { return }
        snapshot.title += " copy"
        // A copy is a one-off even when the original repeats; duplicating a
        // series into a second identical series is almost never the intent.
        snapshot.repeatsWeekly = false
        snapshot.repeatDays = [block.day]
        create(snapshot, inWeekStarting: weekStart, actionName: "Duplicate Event")
    }

    // MARK: Snapshots

    func snapshot(of block: DayBlock) -> EventSnapshot? {
        guard let event = bridge.event(for: block) else { return nil }

        let days = event.recurrenceRules?.first?.daysOfTheWeek?
            .compactMap { Weekday(ekWeekday: $0.dayOfTheWeek) } ?? []

        return EventSnapshot(
            title: event.title ?? "",
            calendarID: event.calendar.calendarIdentifier,
            date: Calendar.current.startOfDay(for: event.startDate),
            start: block.start,
            end: block.end,
            repeatDays: days.isEmpty ? [block.day] : days.sorted { $0.rawValue < $1.rawValue },
            repeatsWeekly: !days.isEmpty,
            note: event.notes ?? "",
            link: event.url?.absoluteString ?? "",
            location: event.location ?? "",
            alarmOffsets: event.alarms?.map(\.relativeOffset) ?? []
        )
    }

    // MARK: Undo plumbing

    private var termEnd: Date { bridge.termEnd }

    private func register(_ name: String, _ body: @escaping (EventEditor) -> Void) {
        guard let undoManager else { return }

        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { body(editor) }
        }
    }

    /// ponytail: undoing a create finds events by matching their slot rather
    /// than by identifier, because a non-repeating multi-day create makes
    /// several events and the ids are only known after each save. Two
    /// identical events in the same slot would be ambiguous — acceptable until
    /// that actually happens.
    private func deleteAll(matching snapshot: EventSnapshot, inWeekStarting weekStart: Date, actionName: String) {
        let targets = bridge.events.filter {
            $0.start == snapshot.start && $0.end == snapshot.end
                && $0.title == snapshot.title
                && snapshot.repeatDays.contains($0.day)
        }

        for block in targets {
            bridge.delete(block, scope: snapshot.repeatsWeekly ? .futureEvents : .thisEvent)
        }
        // Without this, undoing a create leaves nothing on the redo stack —
        // every other operation here re-registers its own inverse the same
        // way, this one just didn't.
        register(actionName) { editor in
            editor.create(snapshot, inWeekStarting: weekStart, actionName: actionName)
        }
        onChange?()
    }

    /// Finds the loaded block for one specific occurrence, falling back from
    /// identifier to day/time/title when the identifier doesn't land on
    /// anything — see `CalendarBridge.findOccurrence` for why the identifier
    /// alone can miss. Logs (never the event's title or other content) when
    /// both miss, so an undo that can't relocate its event shows up
    /// somewhere instead of silently falling off the stack.
    private func block(identifier: String, day: Weekday, start: Int, end: Int, title: String, action: String) -> DayBlock? {
        let found = CalendarBridge.findOccurrence(
            in: bridge.events, identifier: identifier, day: day, start: start, end: end, title: title
        )
        if found == nil {
            print("EventEditor.\(action): undo couldn't relocate its event — identifier and day/time/title both missed.")
        }
        return found
    }

    private func moveBack(
        to snapshot: EventSnapshot,
        identifier: String,
        day: Weekday,
        start: Int,
        end: Int,
        title: String,
        scope: CalendarBridge.EditScope,
        actionName: String
    ) {
        guard let block = block(identifier: identifier, day: day, start: start, end: end, title: title, action: "move")
        else { return }
        move(block, to: snapshot.date, start: snapshot.start, end: snapshot.end,
             scope: scope, actionName: actionName)
    }

    private func renameBack(to snapshot: EventSnapshot, identifier: String, day: Weekday, currentTitle: String, scope: CalendarBridge.EditScope) {
        guard let block = block(identifier: identifier, day: day, start: snapshot.start, end: snapshot.end, title: currentTitle, action: "rename")
        else { return }
        rename(block, to: snapshot.title, scope: scope)
    }

    private func setDetailsBack(to snapshot: EventSnapshot, identifier: String, day: Weekday, title: String, scope: CalendarBridge.EditScope) {
        guard let block = block(identifier: identifier, day: day, start: snapshot.start, end: snapshot.end, title: title, action: "setDetails")
        else { return }
        setDetails(block, note: snapshot.note, link: snapshot.link, scope: scope)
    }
}
