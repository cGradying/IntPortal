namespace PUPSISPortal.Core;

/// <summary>
/// Maps points in the week grid to days and times.
///
/// This exists because the creation gesture used to live inside each day
/// column, which made a horizontal drag physically unable to cross into
/// another day. One layer spans all seven columns and resolves x itself.
/// </summary>
public class GridGeometry
{
    /// <summary>
    /// Width of the whole seven-column body, gutter excluded.
    /// </summary>
    public double Width { get; }

    public double Height { get; }

    public (int start, int end) Axis { get; }

    /// <summary>
    /// Horizontal gap drawn between columns.
    /// </summary>
    public double ColumnSpacing { get; }

    public GridGeometry(
        double width,
        double height,
        (int start, int end) axis,
        double columnSpacing = 5)
    {
        Width = width;
        Height = height;
        Axis = axis;
        ColumnSpacing = columnSpacing;
    }

    public double ColumnWidth
    {
        get
        {
            var days = (double)7; // Weekday.allCases.count in Swift
            return (Width - ColumnSpacing * (days - 1)) / days;
        }
    }

    /// <summary>
    /// Leading edge of a day's column.
    /// </summary>
    public double X(Weekday day)
    {
        return ((int)day - 1) * (ColumnWidth + ColumnSpacing);
    }

    /// <summary>
    /// Which column a point falls in. Clamped, so a drag that runs off either
    /// side of the grid keeps selecting the first or last day instead of
    /// stopping dead.
    /// </summary>
    public Weekday Day(double x)
    {
        if (ColumnWidth <= 0)
            return Weekday.Monday;

        var index = (int)Math.Floor(x / (ColumnWidth + ColumnSpacing));
        var clamped = Math.Min(Math.Max(index, 0), 6); // Weekday.allCases.count - 1
        return (Weekday)(clamped + 1);
    }

    /// <summary>
    /// Vertical position to minutes from midnight.
    /// </summary>
    public int Minutes(double y)
    {
        return TimeSnap.Minutes(y, Axis, Height);
    }

    /// <summary>
    /// The rectangle a block occupies, for positioning and for anchoring the
    /// editor popover.
    /// </summary>
    public GridRect Rect(Weekday day, int start, int end)
    {
        var span = Math.Max(Axis.end - Axis.start, 1);
        var top = (double)(start - Axis.start) / span * Height;
        var bottom = (double)(end - Axis.start) / span * Height;

        return new GridRect(
            X(day),
            top,
            ColumnWidth,
            Math.Max(bottom - top, 1)
        );
    }

    /// <summary>
    /// A drag, resolved into the days it covered and the time range it drew.
    ///
    /// Vertical decides the time, horizontal decides the days, and either can
    /// be drawn in either direction.
    /// </summary>
    public DragRange Drag(double originX, double originY, double currentX, double currentY)
    {
        var days = Days(originX, currentX);
        var range = TimeSnap.Range(Minutes(originY), Minutes(currentY), Axis);

        return new DragRange
        {
            Days = days,
            Start = range.start,
            End = range.end
        };
    }

    /// <summary>
    /// Every column between two x positions, inclusive, in weekday order
    /// regardless of which way the drag was drawn.
    /// </summary>
    public List<Weekday> Days(double startX, double endX)
    {
        var first = (int)Day(Math.Min(startX, endX));
        var last = (int)Day(Math.Max(startX, endX));

        var result = new List<Weekday>();
        for (int i = first; i <= last; i++)
        {
            result.Add((Weekday)i);
        }
        return result;
    }

    /// <summary>
    /// Weekdays touched by a rubber-band rectangle, for multi-select.
    /// </summary>
    public List<Weekday> Days(GridRect rect)
    {
        return Days(rect.MinX, rect.MaxX);
    }
}
