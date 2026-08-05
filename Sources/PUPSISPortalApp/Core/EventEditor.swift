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
        if snapshot.repeatsWeekly {
            guard bridge.add(
                title: snapshot.title,
                on: snapshot.date,
                start: snapshot.start,
                end: snapshot.end,
                repeatingOn: snapshot.repeatDays,
                until: termEnd,
                calendarID: snapshot.calendarID
            ) != nil else { return }
        } else {
            for date in snapshot.dates(inWeekStarting: weekStart) {
                _ = bridge.add(
                    title: snapshot.title,
                    on: date,
                    start: snapshot.start,
                    end: snapshot.end,
                    calendarID: snapshot.calendarID
                )
            }
        }

        register(actionName) { editor in
            editor.deleteAll(matching: snapshot, inWeekStarting: weekStart)
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
        register(actionName) { editor in
            editor.create(snapshot, inWeekStarting: weekStart, actionName: actionName)
        }
        onChange?()
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

        bridge.reschedule(block, to: date, start: start, end: end, scope: scope)
        register(actionName) { editor in
            // The block is stale after a reload, so undo goes back through the
            // freshly-loaded occurrence at the moved-to slot.
            editor.moveBack(to: before, scope: scope, actionName: actionName)
        }
        onChange?()
    }

    func rename(_ block: DayBlock, to title: String, scope: CalendarBridge.EditScope) {
        guard let before = snapshot(of: block) else { return }

        bridge.rename(block, to: title, scope: scope)
        register("Rename Event") { editor in
            editor.renameBack(to: before, scope: scope)
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
            repeatsWeekly: !days.isEmpty
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
    private func deleteAll(matching snapshot: EventSnapshot, inWeekStarting weekStart: Date) {
        let targets = bridge.events.filter {
            $0.start == snapshot.start && $0.end == snapshot.end
                && $0.title == snapshot.title
                && snapshot.repeatDays.contains($0.day)
        }

        for block in targets {
            bridge.delete(block, scope: snapshot.repeatsWeekly ? .futureEvents : .thisEvent)
        }
        onChange?()
    }

    private func moveBack(to snapshot: EventSnapshot, scope: CalendarBridge.EditScope, actionName: String) {
        guard let block = bridge.events.first(where: { $0.title == snapshot.title }) else { return }
        move(block, to: snapshot.date, start: snapshot.start, end: snapshot.end,
             scope: scope, actionName: actionName)
    }

    private func renameBack(to snapshot: EventSnapshot, scope: CalendarBridge.EditScope) {
        guard let block = bridge.events.first(where: {
            $0.start == snapshot.start && $0.end == snapshot.end
        }) else { return }
        rename(block, to: snapshot.title, scope: scope)
    }
}
