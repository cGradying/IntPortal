namespace PUPSISPortal.Core;

/// <summary>
/// Builds a standard iCalendar (`.ics`) document from the scraped schedule, so
/// the term can be shared or imported anywhere — Google Calendar's web import,
/// a phone, another app — without going through system calendar APIs.
///
/// Pure by design: no persistence, no preferences, no clock beyond what the
/// caller passes. One `VEVENT` per class, repeating weekly until the term ends.
///
/// Times are written as *floating* local time (no timezone): a personal class
/// schedule is naturally read in whatever timezone the student is in, and it
/// keeps the file free of a bulky `VTIMEZONE` block. Because `DTSTART` is
/// floating, `UNTIL` is floating too, as RFC 5545 requires.
/// </summary>
public static class ICSExporter
{
    /// <summary>
    /// `status` resolves each class's term status; vacant classes are left out
    /// and online ones are marked, matching the export logic so the file and
    /// any other export never disagree.
    ///
    /// ponytail: term status only, not per-week — a single repeating VEVENT can't
    /// carry a one-week exception, the same limit any weekly-repeat export has.
    /// </summary>
    public static string Ics(
        List<ClassSession> sessions,
        DateTime weekStart,
        DateTime termEnd,
        Func<ClassSession, SessionStatus>? status = null,
        DateTime? now = null)
    {
        status ??= _ => SessionStatus.Regular;
        now ??= DateTime.Now;

        // End of the term's last day, so a class on that day still repeats onto it.
        var lastDay = ClassRecurrence.LastMoment(termEnd);
        var stamp = ClassRecurrence.Utc(now.Value);

        var lines = new List<string>
        {
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//PUPSISPortal//Schedule//EN",
            "CALSCALE:GREGORIAN",
        };

        foreach (var session in sessions)
        {
            var sessionStatus = status(session);
            var plan = ClassExportPlan(sessionStatus);
            if (plan is null)
                continue;

            var (titleSuffix, location) = plan.Value;

            var day = session.Day.DateInWeekStarting(weekStart);
            var startDateTime = day.AddMinutes(session.Start);
            var endDateTime = day.AddMinutes(session.End);

            lines.Add("BEGIN:VEVENT");
            lines.Add($"UID:{session.Id}@pupsisportal");
            lines.Add($"DTSTAMP:{stamp}");
            lines.Add($"DTSTART:{ClassRecurrence.Floating(startDateTime)}");
            lines.Add($"DTEND:{ClassRecurrence.Floating(endDateTime)}");
            lines.Add($"RRULE:{ClassRecurrence.RRule(session.Day, ClassRecurrence.Floating(lastDay))}");
            lines.Add($"SUMMARY:{Escape(session.SubjectCode + (titleSuffix ?? ""))}");
            lines.Add($"DESCRIPTION:{Escape(Description(session))}");
            if (!string.IsNullOrEmpty(location))
            {
                lines.Add($"LOCATION:{Escape(location)}");
            }
            lines.Add("END:VEVENT");
        }

        lines.Add("END:VCALENDAR");

        // RFC 5545 lines are CRLF-terminated and folded at 75 octets.
        return string.Join("\r\n", lines.Select(Fold)) + "\r\n";
    }

    // MARK: Detail

    private static string Description(ClassSession session)
    {
        return string.IsNullOrEmpty(session.Faculty)
            ? session.Description
            : $"{session.Description}\n{session.Faculty}";
    }

    private static string Escape(string text)
    {
        return text
            .Replace("\\", "\\\\")
            .Replace(";", "\\;")
            .Replace(",", "\\,")
            .Replace("\n", "\\n");
    }

    /// <summary>
    /// Fold a content line to ≤75 characters, continuation lines beginning with a
    /// space. ponytail: folds on character count, not UTF-8 octets — the schedule
    /// data here is effectively ASCII; switch to a byte walk if non-Latin content
    /// ever lands in a field.
    /// </summary>
    private static string Fold(string line)
    {
        if (line.Length <= 75)
            return line;

        var result = "";
        var remaining = line;
        var limit = 75;

        while (remaining.Length > limit)
        {
            result += remaining.Substring(0, limit) + "\r\n ";
            remaining = remaining.Substring(limit);
            limit = 74; // the leading space costs one character on continuation lines
        }

        result += remaining;
        return result;
    }

    /// <summary>
    /// Determines if a class should be exported and how. Returns null for vacant
    /// classes, otherwise a tuple of (titleSuffix, location).
    /// </summary>
    private static (string? titleSuffix, string? location)? ClassExportPlan(SessionStatus sessionStatus)
    {
        return sessionStatus switch
        {
            SessionStatus.Regular => ("", null),
            SessionStatus.Online => (" (Online)", "Online"),
            SessionStatus.Vacant => null,
            _ => null,
        };
    }
}
