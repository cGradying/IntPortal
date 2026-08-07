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
}
