namespace PUPSISPortal.Core;

/// <summary>
/// What a create-drag produced: a time range plus the days it applies to.
/// </summary>
public record DragRange
{
    public required List<Weekday> Days { get; init; }
    public required int Start { get; init; }
    public required int End { get; init; }

    public bool IsMultiDay => Days.Count > 1;

    /// <summary>
    /// The day the event itself starts on; the rest come from recurrence.
    /// </summary>
    public Weekday AnchorDay => Days.FirstOrDefault(Weekday.Monday);
}
