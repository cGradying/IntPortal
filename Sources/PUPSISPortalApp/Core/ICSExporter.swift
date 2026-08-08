import Foundation

/// Builds a standard iCalendar (`.ics`) document from the scraped schedule, so
/// the term can be shared or imported anywhere — Google Calendar's web import,
/// a phone, another app — without going through EventKit.
///
/// Pure by design: no EventKit, no `Preferences`, no clock beyond what the
/// caller passes. One `VEVENT` per class, repeating weekly until the term ends.
///
/// Times are written as *floating* local time (no timezone): a personal class
/// schedule is naturally read in whatever timezone the student is in, and it
/// keeps the file free of a bulky `VTIMEZONE` block. Because `DTSTART` is
/// floating, `UNTIL` is floating too, as RFC 5545 requires.
enum ICSExporter {
    /// `status` resolves each class's term status; vacant classes are left out
    /// and online ones are marked, matching `CalendarBridge.exportClasses` so the
    /// file and the EventKit export never disagree.
    ///
    /// ponytail: term status only, not per-week — a single repeating VEVENT can't
    /// carry a one-week exception, the same limit the EventKit export documents.
    static func ics(
        for sessions: [ClassSession],
        weekStart: Date,
        until termEnd: Date,
        status: (ClassSession) -> SessionStatus = { _ in .regular },
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> String {
        // End of the term's last day, so a class on that day still repeats onto it.
        let lastDay = calendar.startOfDay(for: termEnd).addingTimeInterval(24 * 60 * 60 - 1)
        let stamp = utcStamp(now)

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//PUPSISPortal//Schedule//EN",
            "CALSCALE:GREGORIAN",
        ]

        for session in sessions {
            guard case let .event(titleSuffix, location) =
                    CalendarBridge.ClassExport.plan(for: status(session)) else { continue }

            let day = session.day.date(inWeekStarting: weekStart, calendar: calendar)
            guard let start = calendar.date(byAdding: .minute, value: session.start, to: day),
                  let end = calendar.date(byAdding: .minute, value: session.end, to: day)
            else { continue }

            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(session.id)@pupsisportal")
            lines.append("DTSTAMP:\(stamp)")
            lines.append("DTSTART:\(floating(start, calendar))")
            lines.append("DTEND:\(floating(end, calendar))")
            lines.append("RRULE:FREQ=WEEKLY;UNTIL=\(floating(lastDay, calendar));BYDAY=\(byDay(session.day))")
            lines.append("SUMMARY:\(escape(session.subjectCode + (titleSuffix ?? "")))")
            lines.append("DESCRIPTION:\(escape(description(for: session)))")
            if let location {
                lines.append("LOCATION:\(escape(location))")
            }
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        // RFC 5545 lines are CRLF-terminated and folded at 75 octets.
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Detail

    private static func description(for session: ClassSession) -> String {
        session.faculty.isEmpty
            ? session.description
            : "\(session.description)\n\(session.faculty)"
    }

    private static func byDay(_ day: Weekday) -> String {
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

    /// Local wall-clock, no timezone — a floating time.
    private static func floating(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// DTSTAMP must be UTC.
    private static func utcStamp(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Fold a content line to ≤75 characters, continuation lines beginning with a
    /// space. ponytail: folds on character count, not UTF-8 octets — the schedule
    /// data here is effectively ASCII; switch to a byte walk if non-Latin content
    /// ever lands in a field.
    private static func fold(_ line: String) -> String {
        guard line.count > 75 else { return line }
        var out = ""
        var remaining = Substring(line)
        var limit = 75
        while remaining.count > limit {
            let idx = remaining.index(remaining.startIndex, offsetBy: limit)
            out += remaining[..<idx] + "\r\n "
            remaining = remaining[idx...]
            limit = 74 // the leading space costs one octet on continuation lines
        }
        out += remaining
        return out
    }
}
