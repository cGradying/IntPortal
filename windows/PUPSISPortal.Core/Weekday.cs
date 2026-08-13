using System.Text.Json.Serialization;

namespace PUPSISPortal.Core;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum Weekday
{
    Monday = 1,
    Tuesday = 2,
    Wednesday = 3,
    Thursday = 4,
    Friday = 5,
    Saturday = 6,
    Sunday = 7,
}

public static class WeekdayExtensions
{
    private static readonly Dictionary<Weekday, string> ShortNames = new()
    {
        { Weekday.Monday, "MON" },
        { Weekday.Tuesday, "TUE" },
        { Weekday.Wednesday, "WED" },
        { Weekday.Thursday, "THU" },
        { Weekday.Friday, "FRI" },
        { Weekday.Saturday, "SAT" },
        { Weekday.Sunday, "SUN" },
    };

    /// <summary>
    /// SIS day codes, longest first — `SUN` and `TH` must be matched before
    /// `S` and `T` or they get swallowed.
    /// </summary>
    private static readonly List<(string code, Weekday day)> DayCodes = new()
    {
        ("SUN", Weekday.Sunday),
        ("TH", Weekday.Thursday),
        ("M", Weekday.Monday),
        ("T", Weekday.Tuesday),
        ("W", Weekday.Wednesday),
        ("F", Weekday.Friday),
        ("S", Weekday.Saturday),
    };

    public static string Short(this Weekday day) => ShortNames[day];

    /// <summary>
    /// System.DayOfWeek numbers weekdays 0 = Sunday ... 6 = Saturday; this enum runs
    /// 1 = Monday … 7 = Sunday, which is the order the grid renders in.
    /// </summary>
    public static Weekday FromSystemDayOfWeek(DayOfWeek dayOfWeek)
    {
        // DayOfWeek: Sun=0, Mon=1, ..., Sat=6
        // Weekday: Mon=1, Tue=2, ..., Sun=7
        // Map: Sun(0) -> 7, Mon(1) -> 1, Tue(2) -> 2, ..., Sat(6) -> 6
        var shifted = ((int)dayOfWeek + 6) % 7 + 1;
        return (Weekday)shifted;
    }

    /// <summary>
    /// Midnight on the Monday of `date`'s week. The grid reads Monday-first.
    /// </summary>
    public static DateTime WeekStart(DateTime date)
    {
        var weekday = FromSystemDayOfWeek(date.DayOfWeek);
        var offset = (int)weekday - 1;
        return date.Date.AddDays(-offset);
    }

    /// <summary>
    /// The date this weekday falls on in the week beginning `weekStart`.
    /// </summary>
    public static DateTime DateInWeekStarting(this Weekday day, DateTime weekStart)
    {
        return weekStart.AddDays((int)day - 1);
    }

    /// <summary>
    /// Get the Weekday for a given date.
    /// </summary>
    public static Weekday On(DateTime date) => FromSystemDayOfWeek(date.DayOfWeek);

    /// <summary>
    /// The next date on/after `date` that `subjectCode` meets, by scheduled
    /// weekday. `null` if the subject isn't in `sessions`. Used to default a
    /// class note's dated log entry to the class it's actually for, rather
    /// than the day it happened to be written.
    /// </summary>
    public static DateTime? NextMeetingDate(string subjectCode, IEnumerable<ClassSession> sessions, DateTime date)
    {
        var weekdays = new HashSet<Weekday>(sessions
            .Where(s => s.SubjectCode == subjectCode)
            .Select(s => s.Day));

        if (weekdays.Count == 0)
            return null;

        var startOfDay = date.Date;
        for (int offset = 0; offset < 7; offset++)
        {
            var candidate = startOfDay.AddDays(offset);
            if (weekdays.Contains(On(candidate)))
                return candidate;
        }

        return null;
    }

    /// <summary>
    /// Parse day codes (e.g., "T/F" → [Tuesday, Friday], "TH" → [Thursday]).
    /// Handles both slash-separated codes and runs like "TTH" / "MW".
    /// </summary>
    public static List<Weekday> TokenizeDays(string token)
    {
        var remainder = token;
        var days = new List<Weekday>();

        while (!string.IsNullOrEmpty(remainder))
        {
            bool found = false;
            foreach (var (code, day) in DayCodes)
            {
                if (remainder.StartsWith(code, StringComparison.Ordinal))
                {
                    days.Add(day);
                    remainder = remainder[code.Length..];
                    found = true;
                    break;
                }
            }

            if (!found)
            {
                // Unrecognized tail — keep what parsed, or empty if nothing parsed yet
                return days.Count > 0 ? days : new List<Weekday>();
            }
        }

        return days;
    }
}
