import SwiftUI

/// What's actually happening with a class meeting. The SIS doesn't say — it
/// only lists the room-and-time it was enrolled as — so this is the user
/// telling the app something it can't scrape.
enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case regular
    case online
    case vacant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular: "In Person"
        case .online: "Online"
        case .vacant: "Vacant"
        }
    }

    var symbol: String {
        switch self {
        case .regular: "building.2"
        case .online: "video.fill"
        case .vacant: "calendar.badge.minus"
        }
    }
}

/// User settings. `UserDefaults` on purpose — these are preferences, unlike
/// the schedule, which is a document and lives in `ScheduleStore`.
///
/// Not `@AppStorage`: that's a view-level property wrapper and doesn't publish
/// from inside an `ObservableObject`, which is exactly where these need to be.
@MainActor
final class Preferences: ObservableObject {
    @Published var theme: ThemeChoice {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    /// Subject code → hex. Absent means "use the palette's default".
    @Published private(set) var subjectColors: [String: String] {
        didSet { defaults.set(try? JSONEncoder().encode(subjectColors), forKey: Key.subjectColors) }
    }

    /// The term-wide default status per meeting, keyed by `ClassSession.id`.
    /// Per *meeting*, not per subject: one section can be in person on Tuesday
    /// and online on Friday. Persisted under the original `sessionStatuses` key,
    /// so marks made before status went per-week load here as "every week" —
    /// which is exactly how they behaved then.
    @Published private(set) var termStatuses: [String: SessionStatus] {
        didSet { defaults.set(try? JSONEncoder().encode(termStatuses), forKey: Key.sessionStatuses) }
    }

    /// This-week exceptions to the term default, keyed by `ClassSession.id` plus
    /// the week they fall in — so "this Tuesday is online" doesn't make every
    /// Tuesday online.
    @Published private(set) var occurrenceStatuses: [String: SessionStatus] {
        didSet { defaults.set(try? JSONEncoder().encode(occurrenceStatuses), forKey: Key.occurrenceStatuses) }
    }

    /// Per-subject colour of the strip drawn around an online class, keyed by
    /// subject code. Absent means "use the palette's online-strip default".
    @Published private(set) var onlineStripColors: [String: String] {
        didSet { defaults.set(try? JSONEncoder().encode(onlineStripColors), forKey: Key.onlineStripColors) }
    }

    /// Event colours, keyed by `DayBlock.groupKey` so a run of connected days
    /// recolours as one thing. EventKit has no per-event colour — events take
    /// their calendar's — so this is ours to keep.
    @Published private(set) var eventColors: [String: String] {
        didSet { defaults.set(try? JSONEncoder().encode(eventColors), forKey: Key.eventColors) }
    }

    /// Which Calendar.app calendars are drawn in the grid. Empty by default —
    /// nothing from the user's calendar appears until they ask for it.
    @Published var visibleCalendarIDs: Set<String> {
        didSet { defaults.set(Array(visibleCalendarIDs), forKey: Key.visibleCalendarIDs) }
    }

    /// Which calendar in-person classes get exported into. Empty until the user
    /// picks — there's no safe default guess for someone else's calendar.
    @Published var exportCalendarID: String {
        didSet { defaults.set(exportCalendarID, forKey: Key.exportCalendarID) }
    }

    /// Which calendar online classes go into. Empty means "same as in-person",
    /// so by default everything lands in one calendar until the user separates
    /// them.
    @Published var onlineExportCalendarID: String {
        didSet { defaults.set(onlineExportCalendarID, forKey: Key.onlineExportCalendarID) }
    }

    /// When exported classes stop repeating. The SIS doesn't publish a term
    /// end, so the user supplies it — a class repeating forever is the kind of
    /// thing you find in your calendar two years later.
    @Published var termEndDate: Date {
        didSet { defaults.set(termEndDate.timeIntervalSince1970, forKey: Key.termEndDate) }
    }

    /// Off until asked for. Turning it on is what triggers the authorization
    /// prompt, so defaulting it to true would prompt at first launch.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    /// Minutes before a class starts. Long enough to walk somewhere.
    @Published var notificationLeadMinutes: Int {
        didSet { defaults.set(notificationLeadMinutes, forKey: Key.notificationLeadMinutes) }
    }

    static let leadOptions = [5, 10, 15, 30]

    /// Meetings marked vacant **for the whole term**, in the form `Notifier` and
    /// `NextClass` want. Term-only on purpose: a weekly-recurring reminder can't
    /// skip a single week's occurrence, so a one-week vacancy stays a visual
    /// thing and doesn't rewrite the reminder.
    var vacantSessionIDs: Set<String> {
        Set(termStatuses.filter { $0.value == .vacant }.keys)
    }

    /// Far enough out to cover a semester, close enough that it's obviously a
    /// guess worth correcting.
    static func defaultTermEnd(from date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 4, to: calendar.startOfDay(for: date)) ?? date
    }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "theme"
        static let subjectColors = "subjectColors"
        static let sessionStatuses = "sessionStatuses"
        static let occurrenceStatuses = "occurrenceStatuses"
        static let onlineStripColors = "onlineStripColors"
        static let visibleCalendarIDs = "visibleCalendarIDs"
        static let exportCalendarID = "exportCalendarID"
        static let onlineExportCalendarID = "onlineExportCalendarID"
        static let eventColors = "eventColors"
        static let termEndDate = "termEndDate"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationLeadMinutes = "notificationLeadMinutes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(ThemeChoice.init(rawValue:)) ?? .auto
        subjectColors = defaults.data(forKey: Key.subjectColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        termStatuses = defaults.data(forKey: Key.sessionStatuses)
            .flatMap { try? JSONDecoder().decode([String: SessionStatus].self, from: $0) } ?? [:]
        occurrenceStatuses = defaults.data(forKey: Key.occurrenceStatuses)
            .flatMap { try? JSONDecoder().decode([String: SessionStatus].self, from: $0) } ?? [:]
        onlineStripColors = defaults.data(forKey: Key.onlineStripColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        eventColors = defaults.data(forKey: Key.eventColors)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        visibleCalendarIDs = Set(defaults.stringArray(forKey: Key.visibleCalendarIDs) ?? [])
        exportCalendarID = defaults.string(forKey: Key.exportCalendarID) ?? ""
        onlineExportCalendarID = defaults.string(forKey: Key.onlineExportCalendarID) ?? ""
        termEndDate = (defaults.object(forKey: Key.termEndDate) as? Double)
            .map(Date.init(timeIntervalSince1970:)) ?? Self.defaultTermEnd()
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        // `integer(forKey:)` returns 0 for a missing key, and 0 is a legal lead
        // ("as it starts") — so check for the key rather than trusting the zero.
        notificationLeadMinutes = (defaults.object(forKey: Key.notificationLeadMinutes) as? Int) ?? 15
    }

    /// The colour an event renders in: the user's pick, else the palette's
    /// deterministic default so two different events don't look identical.
    func color(forEvent groupKey: String, in palette: Palette) -> Color {
        eventColors[groupKey].flatMap(Color.init(hex:)) ?? palette.color(for: groupKey)
    }

    func setEventColor(_ color: Color, for groupKey: String) {
        guard let hex = color.hex else { return }
        eventColors[groupKey] = hex
    }

    func resetEventColor(for groupKey: String) {
        eventColors[groupKey] = nil
    }

    func hasCustomEventColor(for groupKey: String) -> Bool {
        eventColors[groupKey] != nil
    }

    func setCalendar(_ id: String, visible: Bool) {
        if visible {
            visibleCalendarIDs.insert(id)
        } else {
            visibleCalendarIDs.remove(id)
        }
    }

    private func occurrenceKey(_ session: ClassSession, on weekStart: Date) -> String {
        "\(session.id)@\(Int(weekStart.timeIntervalSince1970))"
    }

    /// The status a meeting shows in a given week: this week's exception if
    /// there is one, otherwise the term default, otherwise in person.
    func status(for session: ClassSession, on weekStart: Date) -> SessionStatus {
        occurrenceStatuses[occurrenceKey(session, on: weekStart)]
            ?? termStatuses[session.id]
            ?? .regular
    }

    /// The status picker sets **this week**. Stored only when it differs from
    /// the term default, so it's a genuine exception and clearing back to the
    /// default drops the key rather than pinning a redundant override.
    func setStatus(_ status: SessionStatus, for session: ClassSession, on weekStart: Date) {
        let base = termStatuses[session.id] ?? .regular
        occurrenceStatuses[occurrenceKey(session, on: weekStart)] = status == base ? nil : status
    }

    func termStatus(for session: ClassSession) -> SessionStatus {
        termStatuses[session.id] ?? .regular
    }

    /// The "every week this term" control. `.regular` clears it. Week exceptions
    /// still win over it, so a term-online class can have one vacant week.
    func setTermStatus(_ status: SessionStatus, for session: ClassSession) {
        termStatuses[session.id] = status == .regular ? nil : status
    }

    /// The colour of the strip drawn around an online class: the user's
    /// per-subject pick, else the palette's theme-aware default.
    func stripColor(for subjectCode: String, in palette: Palette) -> Color {
        onlineStripColors[subjectCode].flatMap(Color.init(hex:)) ?? palette.onlineStrip
    }

    func setStripColor(_ color: Color, for subjectCode: String) {
        guard let hex = color.hex else { return }
        onlineStripColors[subjectCode] = hex
    }

    func resetStripColor(for subjectCode: String) {
        onlineStripColors[subjectCode] = nil
    }

    func hasCustomStripColor(for subjectCode: String) -> Bool {
        onlineStripColors[subjectCode] != nil
    }

    /// The color a subject actually renders in: the user's pick if they made
    /// one, otherwise the palette's deterministic default.
    func color(for subjectCode: String, in palette: Palette) -> Color {
        subjectColors[subjectCode].flatMap(Color.init(hex:)) ?? palette.color(for: subjectCode)
    }

    func setColor(_ color: Color, for subjectCode: String) {
        guard let hex = color.hex else { return }
        subjectColors[subjectCode] = hex
    }

    func resetColor(for subjectCode: String) {
        subjectColors[subjectCode] = nil
    }

    func hasCustomColor(for subjectCode: String) -> Bool {
        subjectColors[subjectCode] != nil
    }
}
