namespace PUPSISPortal.Core;

/// <summary>
/// Shared weekly-recurrence bits for exporting a class as a repeating event —
/// used by both the `.ics` file export and the Google Calendar export so the two
/// can't drift on how a class repeats or when it stops.
///
/// Pure and value-only; no EventKit, no network.
/// </summary>
public static class ClassRecurrence
{
    /// <summary>
    /// iCalendar BYDAY code for a weekday.
    /// </summary>
    public static string ByDay(Weekday day) => day switch
    {
        Weekday.Monday => "MO",
        Weekday.Tuesday => "TU",
        Weekday.Wednesday => "WE",
        Weekday.Thursday => "TH",
        Weekday.Friday => "FR",
        Weekday.Saturday => "SA",
        Weekday.Sunday => "SU",
        _ => throw new ArgumentException($"Unknown weekday: {day}")
    };

    /// <summary>
    /// End of the term's last day, so a class on that day still repeats onto it.
    /// </summary>
    public static DateTime LastMoment(DateTime termEnd)
    {
        return termEnd.Date.AddDays(1).AddSeconds(-1);
    }

    /// <summary>
    /// Local wall-clock timestamp YYYYMMDDTHHMMSS, no timezone — a floating time,
    /// which is what the .ics export uses.
    /// </summary>
    public static string Floating(DateTime date)
    {
        return date.ToString("yyyyMMddTHHmmss");
    }

    /// <summary>
    /// UTC timestamp YYYYMMDDTHHMMSSZ — used for DTSTAMP and for Google's
    /// RRULE UNTIL, which must be UTC when the event start carries a timezone.
    /// </summary>
    public static string Utc(DateTime date)
    {
        // Ensure we're working with UTC
        var utcDate = date.Kind == DateTimeKind.Utc ? date : date.ToUniversalTime();
        return utcDate.ToString("yyyyMMddTHHmmssZ");
    }

    /// <summary>
    /// A weekly RRULE value (no RRULE: prefix) ending on `until` — a
    /// preformatted timestamp so the caller decides floating (.ics) vs UTC
    /// (Google).
    /// </summary>
    public static string RRule(Weekday day, string until)
    {
        return $"FREQ=WEEKLY;UNTIL={until};BYDAY={ByDay(day)}";
    }
}
