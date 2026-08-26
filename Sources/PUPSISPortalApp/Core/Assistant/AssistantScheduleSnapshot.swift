import Foundation

/// What "now" and "the schedule" actually mean for the assistant, computed
/// once per turn and folded into the system prompt — the fix for the model
/// never being told today's date and having to invent every `yyyy-MM-dd`
/// argument from nothing.
///
/// Two things, both deterministic, neither trusting the model to compute:
/// - `dateReference`: today plus the next 13 days, each paired with its
///   weekday. "Tomorrow" becomes a lookup against this table, not date
///   arithmetic — confirmed unreliable even *with* today's date given,
///   which is why this exists instead of just stating today's date alone.
/// - `weeklyPattern`: every class, resolved through the same term-wide
///   status/time `set_class_status`/`set_class_time` already write to
///   (`Preferences.termStatus(for:)`/`termTime(for:)`) — the pattern that
///   actually repeats every week until the term ends, not just today's.
///
/// Plain closures rather than a `Preferences` dependency, matching this
/// codebase's existing convention (`RAGQuery`'s injectable tunables) — keeps
/// this pure and testable without a `@MainActor` hop.
struct AssistantScheduleSnapshot: Equatable {
    struct DateReferenceEntry: Equatable, Codable {
        let date: String
        let weekday: String
        let label: String?
    }

    struct PatternEntry: Equatable, Codable {
        let subjectCode: String
        let weekday: String
        let start: String
        let end: String
        let status: String
    }

    let now: Date
    let dateReference: [DateReferenceEntry]
    let weeklyPattern: [PatternEntry]
    let termEnd: Date?

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    init(
        now: Date,
        sessions: [ClassSession],
        termEnd: Date?,
        status: (ClassSession) -> SessionStatus,
        time: (ClassSession) -> (start: Int, end: Int),
        referenceDays: Int = 14,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.termEnd = termEnd

        let startOfToday = calendar.startOfDay(for: now)
        self.dateReference = (0..<referenceDays).compactMap { offset -> DateReferenceEntry? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { return nil }
            let label = offset == 0 ? "today" : (offset == 1 ? "tomorrow" : nil)
            return DateReferenceEntry(
                date: Self.dateFormat.string(from: date),
                weekday: Weekday.on(date, calendar: calendar).short,
                label: label
            )
        }

        self.weeklyPattern = sessions
            .sorted { ($0.day.rawValue, $0.start) < ($1.day.rawValue, $1.start) }
            .map { session in
                let resolvedTime = time(session)
                return PatternEntry(
                    subjectCode: session.subjectCode,
                    weekday: session.day.short,
                    start: ClassSession.format(resolvedTime.start),
                    end: ClassSession.format(resolvedTime.end),
                    status: status(session).label
                )
            }
    }

    /// The block folded into the system prompt — plain lines, not JSON, same
    /// convention `AssistantContext.rendered` already follows.
    var rendered: String {
        var lines = [
            "Right now: \(Weekday.on(now).short), \(Self.dateFormat.string(from: now)), \(Self.timeFormat.string(from: now)).",
        ]

        let referenceLines = dateReference.map { entry in
            entry.label.map { "\(entry.date) = \(entry.weekday) (\($0))" } ?? "\(entry.date) = \(entry.weekday)"
        }
        lines.append("Date reference (use this to resolve \"tomorrow\"/\"next Friday\" — never compute a date yourself):\n" + referenceLines.joined(separator: "\n"))

        if weeklyPattern.isEmpty {
            lines.append("No recurring classes.")
        } else {
            let until = termEnd.map { "through \(Self.dateFormat.string(from: $0))" } ?? "with no end date set"
            let patternLines = weeklyPattern.map { "\($0.subjectCode) \($0.weekday) \($0.start)-\($0.end) (\($0.status))" }
            lines.append("Recurring weekly schedule, repeats every week \(until):\n" + patternLines.joined(separator: "\n"))
        }

        return lines.joined(separator: "\n\n")
    }

    /// The same facts as `rendered`, for the file on disk
    /// (`~/Library/Application Support/PUPSISPortal/assistant-schedule.json`)
    /// — one source of truth, not a second summarization of the schedule to
    /// keep in sync with the first.
    var jsonData: Data? {
        struct Payload: Encodable {
            let now: Date
            let dateReference: [DateReferenceEntry]
            let weeklyPattern: [PatternEntry]
            let termEnd: Date?
        }
        return try? JSONEncoder().encode(Payload(now: now, dateReference: dateReference, weeklyPattern: weeklyPattern, termEnd: termEnd))
    }

    /// Writes `jsonData` to disk, same atomic-write + owner-only-permissions
    /// convention as `ScheduleStore`/`NotesStore` — the "shared JSON file"
    /// the student (or another platform's client) can read directly.
    func save(to url: URL = Self.fileURL) {
        guard let data = jsonData else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static let fileURL: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("assistant-schedule.json")
    }()
}
