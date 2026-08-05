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
