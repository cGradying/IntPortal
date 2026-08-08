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
        let lastDay = ClassRecurrence.lastMoment(of: termEnd, calendar: calendar)
        let stamp = ClassRecurrence.utc(now)

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
            lines.append("DTSTART:\(ClassRecurrence.floating(start, calendar))")
            lines.append("DTEND:\(ClassRecurrence.floating(end, calendar))")
            lines.append("RRULE:\(ClassRecurrence.rrule(day: session.day, until: ClassRecurrence.floating(lastDay, calendar)))")
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
