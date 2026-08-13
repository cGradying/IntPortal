namespace PUPSISPortal.Core;

/// <summary>
/// One class block on one day. A course split into Lec/Lab, or meeting on
/// two days, produces one ClassSession per occurrence.
/// </summary>
public record ClassSession
{
    public required string SubjectCode { get; set; }
    public required string Description { get; set; }
    public required string Faculty { get; set; }
    public required Weekday Day { get; set; }
    /// <summary>
    /// Minutes from midnight.
    /// </summary>
    public required int Start { get; set; }
    /// <summary>
    /// Minutes from midnight.
    /// </summary>
    public required int End { get; set; }

    /// <summary>
    /// Derived, not stored: a UUID default would block synthesized JSON serialization,
    /// and hand every decoded session a new identity. Identity here is positional
    /// anyway — equality already compares these same fields.
    /// </summary>
    public string Id => $"{SubjectCode}-{(int)Day}-{Start}-{End}";

    public int Duration => Math.Max(End - Start, 0);

    public string TimeLabel => $"{Format(Start)} – {Format(End)}";

    /// <summary>
    /// Format minutes from midnight as "H:MMAM/PM" or "HAM/PM" if minutes == 0.
    /// </summary>
    public static string Format(int minutes)
    {
        var hour24 = minutes / 60;
        var minute = minutes % 60;
        var period = hour24 >= 12 ? "PM" : "AM";
        var hour = hour24 % 12;
        if (hour == 0) hour = 12;

        return minute == 0
            ? $"{hour}{period}"
            : $"{hour}:{minute:D2}{period}";
    }
}
