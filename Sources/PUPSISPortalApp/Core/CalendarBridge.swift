import EventKit
import SwiftUI

/// A calendar the user can tick in Settings.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
    /// The account it belongs to — "Google", "iCloud", "On My Mac". Lets the UI
    /// show which are Google, since Google calendars reach the app through
    /// EventKit once the account is added in System Settings.
    let source: String
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

    /// When recurring events stop repeating. Mirrored from `Preferences` so
    /// writers don't each need a reference to it.
    var termEnd: Date = Preferences.defaultTermEnd()

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
            .map {
                CalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: Color(nsColor: $0.color),
                    source: $0.source?.title ?? "Other"
                )
            }
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
        let matches = store.events(matching: predicate)

        // Hold on to the EKEvent instances. A recurring event's occurrences all
        // share one eventIdentifier, so store.event(withIdentifier:) hands back
        // the *master* — editing through it would silently rewrite the whole
        // series when the user dragged a single Tuesday.
        occurrences = [:]
        events = matches
            // Skip what this app exported. Ticking the export calendar
            // otherwise draws every class twice: once from the SIS scrape and
            // once as our own copy read back. The export stays in Calendar.app
            // and on the phone — it just stops echoing into the app that
            // wrote it.
            .filter { !Self.isOurExport($0) }
            .compactMap { event in
                guard let block = Self.block(from: event, calendar: calendar) else { return nil }
                occurrences[block.id] = event
                return block
            }
    }

    nonisolated static func isOurExport(_ event: EKEvent) -> Bool {
        event.notes?.contains(exportTag) == true
    }

    /// Today's events from the given calendars, as render blocks — without
    /// touching the `@Published events` the week grid drives. The Today screen
    /// folds these in beside classes to compute free time around the real day.
    /// Our own class export is filtered out so it doesn't double up, and all-day
    /// events are dropped (they own no slot in an hour timeline).
    func todayBlocks(calendarIDs: Set<String>, on day: Date) -> [DayBlock] {
        events(on: day, calendarIDs: calendarIDs)
    }

    /// Read-only, single-day version of `load(weekStart:calendarIDs:)`. Used by
    /// the assistant's `read_date`/`move_event` tools so a question about an
    /// arbitrary date never disturbs the week the user is actually looking at
    /// — same reasoning `todayBlocks` already documented for itself, which now
    /// calls through here. Unlike `todayBlocks`, this also seeds `occurrences`
    /// (merged in, not reset) so a block it returns can be moved through the
    /// normal `EventEditor.move` path afterward, exactly as if that day's week
    /// had been loaded.
    func events(on day: Date, calendarIDs: Set<String>) -> [DayBlock] {
        guard access == .granted, !calendarIDs.isEmpty else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let wanted = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !wanted.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: wanted)
        return store.events(matching: predicate)
            .filter { !Self.isOurExport($0) }
            .compactMap { event in
                guard let block = Self.block(from: event, calendar: calendar) else { return nil }
                occurrences[block.id] = event
                return block
            }
    }

    /// The exact `EKEvent` a block was built from, keyed by block id.
    private var occurrences: [String: EKEvent] = [:]

    func event(for block: DayBlock) -> EKEvent? { occurrences[block.id] }

    /// True when a block belongs to a repeating event, so callers know to ask
    /// whether an edit applies to one occurrence or the whole series.
    func isRecurring(_ block: DayBlock) -> Bool {
        occurrences[block.id]?.hasRecurrenceRules == true
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
            // Occurrence date, not just the identifier: three occurrences of
            // one weekly event land in the same week, and a shared id would
            // collapse them into a single block for both SwiftUI and
            // BlockLayout.
            id: Self.blockID(identifier: identifier, occurrence: start),
            day: Weekday.on(start, calendar: calendar),
            start: startMinutes,
            end: endMinutes,
            title: event.title ?? "Untitled",
            subtitle: "\(ClassSession.format(startMinutes)) – \(ClassSession.format(endMinutes))",
            // Occurrences of one series share the identifier, so they group
            // even if their titles were edited apart.
            groupKey: event.hasRecurrenceRules ? "series-\(identifier)" : nil
        )
    }

    /// Pure string building, so it stays callable off the main actor.
    nonisolated static func blockID(identifier: String, occurrence: Date) -> String {
        "\(identifier)@\(Int(occurrence.timeIntervalSince1970))"
    }

    // MARK: Writing

    /// Creates one event. A drag across several days becomes a *single* event
    /// with a weekday recurrence rule rather than one event per day — editing
    /// it later edits the whole band, and the days in between stay free.
    ///
    /// Returns the new event's identifier so an undo can find it again.
    @discardableResult
    func add(
        title: String,
        on date: Date,
        start: Int,
        end: Int,
        repeatingOn days: [Weekday] = [],
        until termEnd: Date? = nil,
        calendarID: String
    ) -> String? {
        guard let target = store.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarID })
                ?? store.defaultCalendarForNewEvents
        else {
            lastError = "No calendar available to add to."
            return nil
        }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let startDate = calendar.date(byAdding: .minute, value: start, to: day),
              let endDate = calendar.date(byAdding: .minute, value: end, to: day)
        else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = target

        // A single day needs no rule — a recurrence of one weekday is just
        // noise in Calendar.app's inspector.
        if days.count > 1 {
            event.recurrenceRules = [Self.weeklyRule(on: days, until: termEnd)]
        }

        do {
            try store.save(event, span: .futureEvents, commit: true)
            lastError = nil
            return event.eventIdentifier
        } catch {
            store.reset()
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Builds a rule from values only — no store access, so it's testable
    /// without a main-actor hop.
    nonisolated static func weeklyRule(on days: [Weekday], until termEnd: Date?) -> EKRecurrenceRule {
        EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: days.map { EKRecurrenceDayOfWeek($0.ekWeekday) },
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: termEnd.map { EKRecurrenceEnd(end: $0) }
        )
    }

    /// Which occurrences an edit applies to. Callers ask the user when the
    /// block is recurring; picking either silently is wrong.
    enum EditScope {
        case thisEvent
        case futureEvents

        var span: EKSpan {
            switch self {
            case .thisEvent: .thisEvent
            case .futureEvents: .futureEvents
            }
        }
    }

    /// Moves an existing event to a new day and time — used by dragging a
    /// block's body or its edges.
    ///
    /// Works from the occurrence captured during `load`, never from
    /// `store.event(withIdentifier:)`, which returns the series master.
    func reschedule(_ block: DayBlock, to date: Date, start: Int, end: Int, scope: EditScope) {
        guard let event = occurrences[block.id] else {
            lastError = "That event is no longer loaded. Refresh and try again."
            return
        }
        guard event.calendar.allowsContentModifications else {
            lastError = "“\(event.calendar.title)” is read-only."
            return
        }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let startDate = calendar.date(byAdding: .minute, value: start, to: day),
              let endDate = calendar.date(byAdding: .minute, value: end, to: day)
        else { return }

        event.startDate = startDate
        event.endDate = endDate
        save(event, scope: scope)
    }

    func delete(_ block: DayBlock, scope: EditScope) {
        guard let event = occurrences[block.id] else {
            lastError = "That event is no longer loaded. Refresh and try again."
            return
        }
        guard event.calendar.allowsContentModifications else {
            lastError = "“\(event.calendar.title)” is read-only."
            return
        }

        do {
            try store.remove(event, span: scope.span, commit: true)
            occurrences[block.id] = nil
            lastError = nil
        } catch {
            store.reset()
            lastError = error.localizedDescription
        }
    }

    func rename(_ block: DayBlock, to title: String, scope: EditScope) {
        guard let event = occurrences[block.id] else { return }
        event.title = title
        save(event, scope: scope)
    }

    private func save(_ event: EKEvent, scope: EditScope) {
        do {
            try store.save(event, span: scope.span, commit: true)
            lastError = nil
        } catch {
            store.reset()
            lastError = error.localizedDescription
        }
    }

    /// How a class is written to the calendar, given its term status. Pure so
    /// the "vacant stays off, online is marked" rule is testable without EventKit.
    ///
    /// Term status, not this week's: the export is a weekly-repeating series, so
    /// it can't carry a single week's exception any more than a reminder can.
    enum ClassExport: Equatable {
        /// Vacant all term — deliberately not on the calendar.
        case skip
        case event(titleSuffix: String?, location: String?)

        static func plan(for status: SessionStatus) -> ClassExport {
            switch status {
            case .vacant: .skip
            case .online: .event(titleSuffix: " (Online)", location: "Online")
            case .regular: .event(titleSuffix: nil, location: nil)
            }
        }
    }

    /// Writes the schedule into a calendar the user picked, as weekly repeats,
    /// clearing this app's previous export first — otherwise every export
    /// stacks another copy of the term on top of the last.
    ///
    /// `status` resolves each session's term status: vacant classes are left off
    /// the calendar and online ones are marked, so the export reflects what the
    /// user set rather than the raw scrape.
    ///
    /// Reports how many events it wrote, so a silent no-op is impossible to
    /// mistake for success.
    func exportClasses(
        _ sessions: [ClassSession],
        weekStart: Date,
        until termEnd: Date,
        toCalendarID id: String,
        onlineCalendarID: String? = nil,
        status: (ClassSession, Date) -> SessionStatus = { _, _ in .regular },
        time: (ClassSession, Date) -> (Int, Int) = { s, _ in (s.start, s.end) }
    ) -> String? {
        guard access == .granted else {
            lastError = "Grant calendar access first."
            return nil
        }
        func writable(_ id: String) -> EKCalendar? {
            store.calendars(for: .event).first { $0.calendarIdentifier == id && $0.allowsContentModifications }
        }
        guard let inPersonTarget = writable(id) else {
            lastError = "That calendar is unavailable or read-only. Pick one you can edit."
            return nil
        }
        // Online classes go to their own calendar if one is set; otherwise they
        // land with the rest.
        let onlineTarget = onlineCalendarID.flatMap(writable) ?? inPersonTarget

        // End of that day, so a class on the last day still gets its meeting.
        let lastDay = Calendar.current.startOfDay(for: termEnd).addingTimeInterval(24 * 60 * 60 - 1)
        guard lastDay > weekStart else {
            lastError = "The end date is before this week — nothing would repeat."
            return nil
        }

        do {
            // Clear both calendars first, or a class that moved calendars would
            // leave a copy behind on the old one.
            var removed = 0
            for target in dedupedCalendars([inPersonTarget, onlineTarget]) {
                removed += try clearExported(from: target)
            }

            // One event per (class, week), placed by that week's resolved status
            // — a single repeating event can't put different weeks on different
            // calendars, and online varies week to week.
            // ponytail: rewrites every meeting on each sync (~classes × weeks);
            // fine at this size, delta-sync if the churn ever bites.
            let calendar = Calendar.current
            var written = 0
            var skipped = 0
            var week = weekStart
            while week <= lastDay {
                for session in sessions {
                    let st = status(session, week)
                    guard case let .event(titleSuffix, location) = ClassExport.plan(for: st) else {
                        skipped += 1
                        continue
                    }
                    let target = st == .online ? onlineTarget : inPersonTarget

                    let day = session.day.date(inWeekStarting: week, calendar: calendar)
                    let (startMinutes, endMinutes) = time(session, week)
                    guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: day),
                          let end = calendar.date(byAdding: .minute, value: endMinutes, to: day),
                          start <= lastDay
                    else { continue }

                    let event = EKEvent(eventStore: store)
                    event.title = session.subjectCode + (titleSuffix ?? "")
                    event.location = location
                    event.notes = "\(session.description)\n\n\(Self.exportTag)"
                    event.startDate = start
                    event.endDate = end
                    event.calendar = target
                    try store.save(event, span: .thisEvent, commit: false)
                    written += 1
                }
                guard let next = calendar.date(byAdding: .day, value: 7, to: week) else { break }
                week = next
            }
            try store.commit()

            lastError = nil
            let replaced = removed > 0 ? ", replacing \(removed)" : ""
            let split = onlineTarget.calendarIdentifier != inPersonTarget.calendarIdentifier
                ? " (online to “\(onlineTarget.title)”)" : ""
            let through = lastDay.formatted(.dateTime.month(.abbreviated).day().year())
            return "Exported \(written) class meeting\(written == 1 ? "" : "s") to “\(inPersonTarget.title)”\(split) through \(through)\(replaced)."
        } catch {
            store.reset()
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Distinct calendars by identifier — in-person and online may be the same
    /// one, and clearing it twice would just waste a query.
    private func dedupedCalendars(_ calendars: [EKCalendar]) -> [EKCalendar] {
        var seen = Set<String>()
        return calendars.filter { seen.insert($0.calendarIdentifier).inserted }
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
