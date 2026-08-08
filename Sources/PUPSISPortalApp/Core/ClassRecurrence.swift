import Foundation

/// Shared weekly-recurrence bits for exporting a class as a repeating event —
/// used by both the `.ics` file export and the Google Calendar export so the two
/// can't drift on how a class repeats or when it stops.
///
/// Pure and value-only; no EventKit, no network.
enum ClassRecurrence {
    /// iCalendar `BYDAY` code for a weekday.
    static func byDay(_ day: Weekday) -> String {
        switch day {
        case .monday: "MO"
        case .tuesday: "TU"
        case .wednesday: "WE"
        case .thursday: "TH"
        case .friday: "FR"
        case .saturday: "SA"
        case .sunday: "SU"
        }
    }

    /// End of the term's last day, so a class on that day still repeats onto it.
    static func lastMoment(of termEnd: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: termEnd).addingTimeInterval(24 * 60 * 60 - 1)
    }

    /// Local wall-clock timestamp `YYYYMMDDTHHMMSS`, no timezone — a floating time,
    /// which is what the `.ics` export uses.
    static func floating(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// UTC timestamp `YYYYMMDDTHHMMSSZ` — used for `DTSTAMP` and for Google's
    /// `RRULE` `UNTIL`, which must be UTC when the event start carries a timezone.
    static func utc(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// A weekly `RRULE` value (no `RRULE:` prefix) ending on `until` — a
    /// preformatted timestamp so the caller decides floating (`.ics`) vs UTC
    /// (Google).
    static func rrule(day: Weekday, until timestamp: String) -> String {
        "FREQ=WEEKLY;UNTIL=\(timestamp);BYDAY=\(byDay(day))"
    }
}
