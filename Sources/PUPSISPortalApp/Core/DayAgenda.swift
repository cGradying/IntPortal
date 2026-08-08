import Foundation

/// Where a class sits relative to right now.
enum ClassPhase {
    case past
    case inSession
    case upcoming
}

/// "What does today look like right now" — the shared reading behind both the
/// Today screen and the menu bar. Pure on purpose: no `Preferences`, no views,
/// no clock of its own. Vacancy arrives as a closure taking the class **and its
/// occurrence date**, so each caller applies its own per-week rule and tomorrow
/// keys to the right week (which can be next week) without this type depending
/// on `Preferences`.
struct DayAgenda {
    struct Item: Identifiable {
        let session: ClassSession
        let phase: ClassPhase
        var id: String { session.id }
    }

    /// Today's non-vacant classes, sorted by start, each tagged with its phase.
    let items: [Item]
    /// The first non-vacant class tomorrow, or `nil`.
    let tomorrowFirst: ClassSession?

    static func make(
        sessions: [ClassSession],
        now: Date,
        isVacant: (ClassSession, Date) -> Bool,
        calendar: Calendar = .current
    ) -> DayAgenda {
        let today = Weekday.on(now, calendar: calendar)
        let nowMinutes = NowLine.minutes(of: now, calendar: calendar)

        let items = sessions
            .filter { $0.day == today && !isVacant($0, now) }
            .sorted { $0.start < $1.start }
            .map { session -> Item in
                let phase: ClassPhase
                if session.end <= nowMinutes { phase = .past }
                else if session.start <= nowMinutes { phase = .inSession }
                else { phase = .upcoming }
                return Item(session: session, phase: phase)
            }

        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrowDay = Weekday.on(tomorrowDate, calendar: calendar)
        let tomorrowFirst = sessions
            .filter { $0.day == tomorrowDay && !isVacant($0, tomorrowDate) }
            .min { $0.start < $1.start }

        return DayAgenda(items: items, tomorrowFirst: tomorrowFirst)
    }

    /// Today's classes that haven't finished — what the menu bar shows, so the
    /// scarce space reads as "now and what's left", not the whole past day.
    var remaining: [Item] {
        items.filter { $0.phase != .past }
    }

    // MARK: Merged timeline (classes + custom calendar events)

    /// A single row in the Today timeline — a class or a calendar event, flattened
    /// to the same shape so free time can be read across both.
    struct AgendaEntry: Identifiable {
        enum Kind: Equatable {
            case klass(ClassSession)
            case event
        }
        let id: String
        /// Minutes from midnight.
        let start: Int
        let end: Int
        let title: String
        let subtitle: String
        let kind: Kind
        let phase: ClassPhase

        var session: ClassSession? {
            if case .klass(let session) = kind { return session }
            return nil
        }
    }

    /// Today's non-vacant classes merged with today's calendar `events`, sorted by
    /// start and phase-tagged — so the Today screen can draw one timeline and its
    /// free stretches span classes *and* the user's own events, not just classes.
    static func timeline(
        classes: [ClassSession],
        events: [DayBlock],
        now: Date,
        isVacant: (ClassSession, Date) -> Bool,
        calendar: Calendar = .current
    ) -> [AgendaEntry] {
        let today = Weekday.on(now, calendar: calendar)
        let nowMinutes = NowLine.minutes(of: now, calendar: calendar)

        func phase(start: Int, end: Int) -> ClassPhase {
            if end <= nowMinutes { return .past }
            if start <= nowMinutes { return .inSession }
            return .upcoming
        }

        let classEntries = classes
            .filter { $0.day == today && !isVacant($0, now) }
            .map { session in
                AgendaEntry(
                    id: "class-\(session.id)",
                    start: session.start, end: session.end,
                    title: session.subjectCode, subtitle: session.description,
                    kind: .klass(session),
                    phase: phase(start: session.start, end: session.end)
                )
            }

        let eventEntries = events
            .filter { $0.day == today }
            .map { block in
                AgendaEntry(
                    id: block.id,
                    start: block.start, end: block.end,
                    title: block.title, subtitle: block.subtitle,
                    kind: .event,
                    phase: phase(start: block.start, end: block.end)
                )
            }

        return (classEntries + eventEntries).sorted { $0.start < $1.start }
    }

    /// Free minutes still ahead today — the ≥15-minute gaps the timeline draws
    /// between consecutive entries, counting only gaps that haven't passed.
    /// Overlapping entries contribute nothing (a negative gap is dropped).
    static func remainingFreeMinutes(_ entries: [AgendaEntry], nowMinutes: Int) -> Int {
        var total = 0
        for i in entries.indices.dropLast() {
            let gap = entries[i + 1].start - entries[i].end
            guard gap >= 15, entries[i + 1].start > nowMinutes else { continue }
            total += gap
        }
        return total
    }
}
