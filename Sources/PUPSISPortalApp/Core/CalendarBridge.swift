import EventKit
import SwiftUI

/// A calendar the user can tick in Settings.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
}

/// Reads Calendar.app into the week grid and writes classes back out.
///
/// One `EKEventStore` for the app, same single-owner shape as
/// `PortalController`'s web view — EventKit caches aggressively and a second
/// store would see stale data after a write.
@MainActor
final class CalendarBridge: ObservableObject {
    enum Access: Equatable {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var access: Access
    @Published private(set) var calendars: [CalendarInfo] = []
    /// Only calendars the account actually lets us write to — subscribed and
    /// birthday calendars are read-only and would fail at save time.
    var writableCalendars: [CalendarInfo] {
        let writable = Set(
            store.calendars(for: .event)
                .filter(\.allowsContentModifications)
                .map(\.calendarIdentifier)
        )
        return calendars.filter { writable.contains($0.id) }
    }

    @Published private(set) var events: [DayBlock] = []
    @Published var lastError: String?

    /// Stamped into the notes of every event this app exports.
    ///
    /// The app used to create its own "PUP Classes" calendar and clear it
    /// wholesale, but creating a calendar needs a writable local or iCloud
    /// source and plenty of accounts don't have one — the export just failed.
    /// Tagging means classes can go into any calendar the user can write to,
    /// and a re-export still only ever deletes events this app wrote.
    static let exportTag = "[PUPSISPortal]"

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
        if access == .granted { calendars = Self.readCalendars(from: store) }

        // Edits made in Calendar.app should show up here without a manual
        // refresh; EventKit posts this whenever its database changes.
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotificationCenter.default.post(name: .calendarStoreChanged, object: nil) }
        }
    }

    deinit {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
    }

    // MARK: Access

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Asked on first enable in Settings, never at launch — a permission
    /// prompt before the user has asked for the feature is just noise.
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
        }
        access = Self.currentAccess()
        calendars = access == .granted ? Self.readCalendars(from: store) : []
    }

    private static func readCalendars(from store: EKEventStore) -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: Reading

    /// No ticked calendars means an empty grid, deliberately: sync ships off
    /// and nothing appears until the user picks what they want to see.
    func load(weekStart: Date, calendarIDs: Set<String>) {
        guard access == .granted, !calendarIDs.isEmpty else {
            events = []
            return
        }

        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return }

        let wanted = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !wanted.isEmpty else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: wanted)
        events = store.events(matching: predicate).compactMap { Self.block(from: $0, calendar: calendar) }
    }

    /// All-day events have no slot in an hour grid, so they're dropped rather
    /// than drawn as a full-height bar over everything.
    ///
    /// ponytail: an event crossing midnight is clamped to its start day rather
    /// than split across two columns. Split it if overnight events show up.
    private static func block(from event: EKEvent, calendar: Calendar) -> DayBlock? {
        guard !event.isAllDay,
              let start = event.startDate,
              let end = event.endDate,
              let identifier = event.eventIdentifier
        else { return nil }

        let startMinutes = NowLine.minutes(of: start, calendar: calendar)
        let endMinutes = calendar.isDate(start, inSameDayAs: end)
            ? NowLine.minutes(of: end, calendar: calendar)
            : 24 * 60

        guard endMinutes > startMinutes else { return nil }

        return DayBlock(
            id: identifier,
            day: Weekday.on(start, calendar: calendar),
            start: startMinutes,
            end: endMinutes,
            title: event.title ?? "Untitled",
            subtitle: "\(ClassSession.format(startMinutes)) – \(ClassSession.format(endMinutes))"
        )
    }

    // MARK: Writing

    func add(title: String, on date: Date, start: Int, end: Int, calendarID: String) {
        guard let target = store.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarID })
                ?? store.defaultCalendarForNewEvents
        else {
            lastError = "No calendar available to add to."
            return
        }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let startDate = calendar.date(byAdding: .minute, value: start, to: day),
              let endDate = calendar.date(byAdding: .minute, value: end, to: day)
        else { return }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = target

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Writes the schedule into a calendar the user picked, as weekly repeats,
    /// clearing this app's previous export first — otherwise every export
    /// stacks another copy of the term on top of the last.
    ///
    /// Reports how many events it wrote, so a silent no-op is impossible to
    /// mistake for success.
    func exportClasses(
        _ sessions: [ClassSession],
        weekStart: Date,
        until termEnd: Date,
        toCalendarID id: String
    ) -> String? {
        guard access == .granted else {
            lastError = "Grant calendar access first."
            return nil
        }
        guard let target = store.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) else {
            lastError = "That calendar is no longer available."
            return nil
        }
        guard target.allowsContentModifications else {
            lastError = "“\(target.title)” is read-only. Pick a calendar you can edit."
            return nil
        }
        // End of that day, so a class on the last day still gets an occurrence.
        let lastDay = Calendar.current.startOfDay(for: termEnd).addingTimeInterval(24 * 60 * 60 - 1)
        guard lastDay > weekStart else {
            lastError = "The end date is before this week — nothing would repeat."
            return nil
        }

        do {
            let removed = try clearExported(from: target)

            let calendar = Calendar.current
            var written = 0
            for session in sessions {
                let day = session.day.date(inWeekStarting: weekStart, calendar: calendar)
                guard let start = calendar.date(byAdding: .minute, value: session.start, to: day),
                      let end = calendar.date(byAdding: .minute, value: session.end, to: day)
                else { continue }

                let event = EKEvent(eventStore: store)
                event.title = session.subjectCode
                event.notes = "\(session.description)\n\n\(Self.exportTag)"
                event.startDate = start
                event.endDate = end
                event.calendar = target
                event.recurrenceRules = [
                    EKRecurrenceRule(
                        recurrenceWith: .weekly,
                        interval: 1,
                        end: EKRecurrenceEnd(end: lastDay)
                    )
                ]

                try store.save(event, span: .futureEvents, commit: false)
                written += 1
            }
            try store.commit()

            lastError = nil
            let replaced = removed > 0 ? ", replacing \(removed)" : ""
            let through = lastDay.formatted(.dateTime.month(.abbreviated).day().year())
            return "Added \(written) class\(written == 1 ? "" : "es") to “\(target.title)” through \(through)\(replaced)."
        } catch {
            store.reset()
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Removes only events carrying this app's tag. Anything the user put in
    /// the same calendar is left alone — this runs against calendars they own
    /// and use, not a scratch one we created.
    @discardableResult
    private func clearExported(from target: EKCalendar) throws -> Int {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .year, value: -1, to: .now),
              let to = calendar.date(byAdding: .year, value: 2, to: .now)
        else { return 0 }

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [target])
        let ours = store.events(matching: predicate).filter {
            $0.notes?.contains(Self.exportTag) == true
        }

        for event in ours {
            try store.remove(event, span: .futureEvents, commit: false)
        }
        if !ours.isEmpty { try store.commit() }
        return ours.count
    }
}

extension Notification.Name {
    /// Posted when EventKit's database changes, so views can reload the week.
    static let calendarStoreChanged = Notification.Name("PUPSISPortal.calendarStoreChanged")
}
