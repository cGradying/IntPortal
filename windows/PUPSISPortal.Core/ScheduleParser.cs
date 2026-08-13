using System.Text.RegularExpressions;

namespace PUPSISPortal.Core;

/// <summary>
/// Turns a scraped SIS schedule row into individual class blocks.
///
/// The schedule cell looks like:
///     "1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM"
/// Days and time ranges are `/`-separated and paired positionally, so the
/// same day twice (`SUN/SUN`) means two blocks that day (Lec then Lab).
/// </summary>
public static class ScheduleParser
{
    public static List<ClassSession> Parse(Dictionary<string, string> row)
    {
        var line = row.TryGetValue("scheduleLine", out var value) ? value : "";
        var result = SplitDaysAndTimes(line);
        if (result == null)
            return new List<ClassSession>();
        var (dayField, timeField) = result.Value;

        var days = dayField
            .Split('/')
            .SelectMany(token => WeekdayExtensions.TokenizeDays(token))
            .ToList();

        var ranges = timeField
            .Split('/')
            .Select(token => ParseRange(token))
            .Where(r => r.HasValue)
            .Select(r => r!.Value)
            .ToList();

        if (days.Count == 0 || ranges.Count == 0)
            return new List<ClassSession>();

        var subjectCode = row.TryGetValue("subjectCode", out var sc) ? sc : "";
        var description = row.TryGetValue("description", out var d) ? d : "";
        var faculty = row.TryGetValue("faculty", out var f) ? f : "";

        // One day with several ranges means the same day meets more than once;
        // otherwise days and ranges line up one-to-one.
        var count = days.Count == 1 ? ranges.Count : Math.Min(days.Count, ranges.Count);
        var sessions = new List<ClassSession>();

        for (int index = 0; index < count; index++)
        {
            var day = days.Count == 1 ? days[0] : days[index];
            var range = ranges[Math.Min(index, ranges.Count - 1)];
            sessions.Add(new ClassSession
            {
                SubjectCode = subjectCode,
                Description = description,
                Faculty = faculty,
                Day = day,
                Start = range.start,
                End = range.end
            });
        }

        return sessions;
    }

    /// <summary>
    /// Pulls the trailing "<DAYS> <TIMES>" off the end of the schedule line,
    /// ignoring the section prefix (which contains digits and hyphens).
    /// </summary>
    private static (string dayField, string timeField)? SplitDaysAndTimes(string line)
    {
        if (string.IsNullOrEmpty(line))
            return null;

        // Pattern: day codes followed by time ranges
        // Day codes: one or more uppercase letters and slashes, at least two letters
        // Time ranges: one or more "H:MM(AM|PM)-H:MM(AM|PM)" separated by slashes
        const string pattern = @"([A-Z]+(?:/[A-Z]+)*)\s+((?:\d{1,2}:\d{2}[AP]M-\d{1,2}:\d{2}[AP]M)(?:/\d{1,2}:\d{2}[AP]M-\d{1,2}:\d{2}[AP]M)*)\s*$";
        var match = Regex.Match(line, pattern);
        if (!match.Success || match.Groups.Count < 3)
            return null;

        var dayField = match.Groups[1].Value;
        var timeField = match.Groups[2].Value;
        return (dayField, timeField);
    }

    /// <summary>
    /// "02:00PM-04:00PM" -> (840, 960) in minutes from midnight.
    /// </summary>
    private static (int start, int end)? ParseRange(string text)
    {
        var trimmed = text.Trim();
        var parts = trimmed.Split('-');
        if (parts.Length != 2)
            return null;

        var start = ParseTime(parts[0]);
        var end = ParseTime(parts[1]);
        if (start == null || end == null)
            return null;

        return (start.Value, end.Value);
    }

    /// <summary>
    /// Parse a time like "02:00PM" or "12:30AM" to minutes from midnight.
    /// Returns null for unparseable input.
    /// </summary>
    private static int? ParseTime(string text)
    {
        var trimmed = text.Trim().ToUpperInvariant();
        if (trimmed.Length < 6)
            return null;

        var period = trimmed[^2..];
        if (period != "AM" && period != "PM")
            return null;

        var clock = trimmed[..^2].Split(':');
        if (clock.Length != 2)
            return null;

        if (!int.TryParse(clock[0], out var hour) || !int.TryParse(clock[1], out var minute))
            return null;

        if (hour < 1 || hour > 12 || minute < 0 || minute >= 60)
            return null;

        if (period == "PM" && hour != 12)
            hour += 12;
        if (period == "AM" && hour == 12)
            hour = 0;

        return hour * 60 + minute;
    }
}
