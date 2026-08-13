namespace PUPSISPortal.Core;

/// <summary>
/// Converting between a point in the grid and a time, kept out of the views so
/// the arithmetic can be tested rather than eyeballed by dragging.
/// </summary>
public static class TimeSnap
{
    /// <summary>
    /// Quarter hours. Fine enough for a real timetable, coarse enough that a
    /// drag lands on a round number instead of 2:07pm.
    /// </summary>
    public const int Step = 15;

    /// <summary>
    /// Shortest event a drag can produce. Below this the block has no room for
    /// its own title and reads as a rendering glitch.
    /// </summary>
    public const int MinimumDuration = 15;

    /// <summary>
    /// Snap a number of minutes to the nearest quarter-hour boundary.
    /// </summary>
    public static int Snap(int minutes, int step = Step)
    {
        return (int)Math.Round((double)minutes / step) * step;
    }

    /// <summary>
    /// Vertical offset in the grid body to minutes from midnight, snapped and
    /// clamped to the drawn range.
    /// </summary>
    public static int Minutes(double y, (int start, int end) axis, double height)
    {
        if (height <= 0)
            return axis.start;

        var span = axis.end - axis.start;
        var raw = axis.start + (y / height) * span;
        return Math.Min(Math.Max(Snap((int)Math.Round(raw)), axis.start), axis.end);
    }

    /// <summary>
    /// A drag start and end into an ordered range, whichever way it was drawn,
    /// never shorter than <see cref="MinimumDuration"/> and never past the axis.
    /// </summary>
    public static (int start, int end) Range(int anchor, int current, (int start, int end) axis)
    {
        var start = Math.Min(anchor, current);
        var end = Math.Max(anchor, current);

        if (end - start < MinimumDuration)
        {
            // Grow away from whichever edge has room, so dragging at the
            // bottom of the day doesn't silently produce nothing.
            if (start + MinimumDuration <= axis.end)
            {
                end = start + MinimumDuration;
            }
            else
            {
                start = Math.Max(axis.start, axis.end - MinimumDuration);
                end = axis.end;
            }
        }

        return (start, end);
    }

    /// <summary>
    /// Moving one edge of an existing block, keeping the other fixed.
    /// </summary>
    public static (int start, int end) Resize(
        int start,
        int end,
        Edge edge,
        int minutes,
        (int start, int end) axis)
    {
        return edge switch
        {
            Edge.Top =>
                (Math.Max(axis.start, Math.Min(minutes, end - MinimumDuration)), end),
            Edge.Bottom =>
                (start, Math.Min(axis.end, Math.Max(minutes, start + MinimumDuration))),
            _ => (start, end)
        };
    }

    public enum Edge
    {
        Top,
        Bottom
    }
}
