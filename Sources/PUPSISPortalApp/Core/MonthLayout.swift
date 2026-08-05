import Foundation

/// How much calendar is on screen. Deliberately two rungs, not four: the week
/// grid is where the schedule is read, and the year view is how you get to a
/// different week. Day and month views would each need their own layout for a
/// job one of these already does.
enum CalendarScale: String, CaseIterable, Identifiable {
    case week
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "Week"
        case .year: "Year"
        }
    }
}

/// Date math for a month grid, kept out of the view so it can be tested.
enum MonthLayout {
    /// Always six full weeks, so every month in the year view is the same
    /// height and the grid doesn't reflow as you scroll. Cells outside the
    /// month are real dates from the neighbouring months, drawn faintly.
    ///
    /// Monday-first, matching the week grid. `Calendar.firstWeekday` would
    /// start on Sunday in a US locale and disagree with the rest of the app.
    static func days(ofMonthContaining date: Date, calendar: Calendar = .current) -> [Date] {
        let firstOfMonth = startOfMonth(containing: date, calendar: calendar)
        let gridStart = Weekday.weekStart(containing: firstOfMonth, calendar: calendar)

        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
    }

    /// The twelve first-of-month dates for a year.
    static func months(in year: Int, calendar: Calendar = .current) -> [Date] {
        (1...12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
    }

    static func isSameMonth(_ date: Date, as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: other, toGranularity: .month)
    }
}
