import EventKit
import Foundation

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var short: String {
        switch self {
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        case .sunday: "SUN"
        }
    }

    /// `Calendar` numbers weekdays 1 = Sunday … 7 = Saturday; this enum runs
    /// 1 = Monday … 7 = Sunday, which is the order the grid renders in.
    static func on(_ date: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: (calendar.component(.weekday, from: date) + 5) % 7 + 1) ?? .monday
    }

    /// EventKit counts weekdays from Sunday = 1, the same convention
    /// `Calendar` uses and the opposite end from this enum's Monday = 1.
    var ekWeekday: EKWeekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    init?(ekWeekday: EKWeekday) {
        switch ekWeekday {
        case .monday: self = .monday
        case .tuesday: self = .tuesday
        case .wednesday: self = .wednesday
        case .thursday: self = .thursday
        case .friday: self = .friday
        case .saturday: self = .saturday
        case .sunday: self = .sunday
        @unknown default: return nil
        }
    }

    /// Midnight on the Monday of `date`'s week. The grid reads Monday-first,
    /// and `Calendar.firstWeekday` is locale-dependent, so don't ask it.
    static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let offset = on(date, calendar: calendar).rawValue - 1
        return calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date))
            ?? calendar.startOfDay(for: date)
    }

    /// The date this weekday falls on in the week beginning `weekStart`.
    func date(inWeekStarting weekStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: rawValue - 1, to: weekStart) ?? weekStart
    }

    /// SIS day codes, longest first — `SUN` and `TH` must be matched before
    /// `S` and `T` or they get swallowed.
    static let codes: [(String, Weekday)] = [
        ("SUN", .sunday),
        ("TH", .thursday),
        ("M", .monday),
        ("T", .tuesday),
        ("W", .wednesday),
        ("F", .friday),
        ("S", .saturday),
    ]
}

/// One class block on one day. A course split into Lec/Lab, or meeting on
/// two days, produces one `ClassSession` per occurrence.
struct ClassSession: Identifiable, Equatable, Codable {
    let subjectCode: String
    let description: String
    let faculty: String
    let day: Weekday
    /// Minutes from midnight.
    let start: Int
    let end: Int

    /// Derived, not stored: a `UUID()` default would block synthesized
    /// `Codable` and hand every decoded session a new identity. Identity here
    /// is positional anyway — `==` already compares these same fields.
    var id: String { "\(subjectCode)-\(day.rawValue)-\(start)-\(end)" }

    var duration: Int { max(end - start, 0) }

    var timeLabel: String {
        "\(ClassSession.format(start)) – \(ClassSession.format(end))"
    }

    static func format(_ minutes: Int) -> String {
        let hour24 = minutes / 60
        let minute = minutes % 60
        let period = hour24 >= 12 ? "PM" : "AM"
        var hour = hour24 % 12
        if hour == 0 { hour = 12 }
        return minute == 0
            ? "\(hour)\(period)"
            : String(format: "%d:%02d%@", hour, minute, period)
    }

    static func == (lhs: ClassSession, rhs: ClassSession) -> Bool {
        lhs.subjectCode == rhs.subjectCode
            && lhs.day == rhs.day
            && lhs.start == rhs.start
            && lhs.end == rhs.end
    }
}
