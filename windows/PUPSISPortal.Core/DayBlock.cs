namespace PUPSISPortal.Core;

/// <summary>
/// One thing drawn in one column. Classes repeat every week; calendar events
/// belong to a date. Flattening both to "a weekday plus minutes" is what lets
/// the grid draw one kind of thing instead of two.
/// </summary>
public class DayBlock : IEquatable<DayBlock>
{
    public enum SourceType { SisClass, CalendarEvent }

    public string Id { get; set; } = "";
    public Weekday Day { get; set; }
    /// <summary>
    /// Minutes from midnight.
    /// </summary>
    public int Start { get; set; }
    public int End { get; set; }
    public string Title { get; set; } = "";
    public string Subtitle { get; set; } = "";
    public SourceType Source { get; set; }
    /// <summary>
    /// For SisClass: the ClassSession itself; null for CalendarEvent.
    /// </summary>
    public ClassSession? Session { get; set; }
    /// <summary>
    /// Blocks sharing this are the same thing on different days — a class that
    /// meets twice a week, or one drag that covered Monday to Wednesday. Used
    /// to draw them as one connected run instead of separate boxes.
    /// </summary>
    public string GroupKey { get; set; } = "";

    public int Duration => Math.Max(End - Start, 0);

    /// <summary>
    /// Default constructor for object initializer usage.
    /// </summary>
    public DayBlock() { }

    /// <summary>
    /// Create a DayBlock from a ClassSession.
    /// </summary>
    public DayBlock(ClassSession session)
    {
        Id = $"class-{session.Id}";
        Day = session.Day;
        Start = session.Start;
        End = session.End;
        Title = session.SubjectCode;
        Subtitle = session.TimeLabel;
        Source = SourceType.SisClass;
        Session = session;
        // The same subject at a different hour is a different run.
        GroupKey = $"class-{session.SubjectCode}-{session.Start}-{session.End}";
    }

    /// <summary>
    /// Create a DayBlock from a calendar event.
    /// </summary>
    public DayBlock(
        string id,
        Weekday day,
        int start,
        int end,
        string title,
        string subtitle,
        string? groupKey = null)
    {
        Id = $"event-{id}";
        Day = day;
        Start = start;
        End = end;
        Title = title;
        Subtitle = subtitle;
        Source = SourceType.CalendarEvent;
        Session = null;
        // A recurring series passes its shared identifier; separate one-off
        // events fall back to matching title and hour, which is what a
        // multi-day drag without a repeat produces.
        GroupKey = groupKey ?? $"event-{title}-{start}-{end}";
    }

    public bool Equals(DayBlock? other)
    {
        if (other == null) return false;
        return Id == other.Id && Day == other.Day && Start == other.Start && End == other.End
            && Title == other.Title && Subtitle == other.Subtitle && Source == other.Source
            && GroupKey == other.GroupKey;
    }

    public override bool Equals(object? obj) => Equals(obj as DayBlock);

    public override int GetHashCode() => Id.GetHashCode();
}

/// <summary>
/// Where a block sits in a run of consecutive days.
///
/// A drag from Monday to Wednesday used to render as three unconnected boxes,
/// which reads as three unrelated things. Squaring the inner corners and
/// closing the column gap makes it read as one bar.
/// </summary>
public enum RunPosition
{
    Single,
    Leading,
    Middle,
    Trailing,
}

public static class RunPositionExtensions
{
    /// <summary>
    /// Everything except the last block in a run reaches across the gap into
    /// the next column.
    /// </summary>
    public static bool BridgesRight(this RunPosition position) =>
        position == RunPosition.Leading || position == RunPosition.Middle;

    public static bool RoundsLeft(this RunPosition position) =>
        position == RunPosition.Single || position == RunPosition.Leading;

    public static bool RoundsRight(this RunPosition position) =>
        position == RunPosition.Single || position == RunPosition.Trailing;
}

/// <summary>
/// Groups blocks that are the same thing on different days and works out which
/// of them form runs of consecutive weekdays.
/// </summary>
public static class BlockRuns
{
    /// <summary>
    /// Only consecutive days join. Monday/Wednesday/Friday classes stay
    /// separate boxes, because bridging them would draw a bar straight through
    /// a Tuesday the class doesn't meet on.
    /// </summary>
    public static Dictionary<string, RunPosition> Positions(IEnumerable<DayBlock> blocks)
    {
        var result = new Dictionary<string, RunPosition>();

        // Group by groupKey
        var grouped = blocks.GroupBy(b => b.GroupKey);

        foreach (var group in grouped)
        {
            var ordered = group.OrderBy(b => (int)b.Day).ToList();

            for (int index = 0; index < ordered.Count; index++)
            {
                var block = ordered[index];
                var previous = index > 0 ? ordered[index - 1] : null;
                var next = index + 1 < ordered.Count ? ordered[index + 1] : null;

                var joinsLeft = previous != null && (int)previous.Day == (int)block.Day - 1;
                var joinsRight = next != null && (int)next.Day == (int)block.Day + 1;

                result[block.Id] = (joinsLeft, joinsRight) switch
                {
                    (false, false) => RunPosition.Single,
                    (false, true) => RunPosition.Leading,
                    (true, true) => RunPosition.Middle,
                    (true, false) => RunPosition.Trailing,
                };
            }
        }

        return result;
    }
}

/// <summary>
/// The vertical range the grid draws.
/// </summary>
public static class GridAxis
{
    /// <summary>
    /// A normal waking day. Fitting the axis to the blocks alone made the grid
    /// jump around as the schedule changed — a 1:30pm–6:30pm week rendered a
    /// completely different shape from a 7:30am one.
    /// </summary>
    public static readonly (int start, int end) DefaultWindow = (start: 6 * 60, end: 22 * 60);

    /// <summary>
    /// Never narrower than the window, and never clips a block: a 6am lab or a
    /// class running past 10pm pushes the edge out rather than being cut off.
    /// Whole hours, so the labels line up with the hour rules.
    /// </summary>
    public static (int start, int end) Hours(
        IEnumerable<DayBlock> blocks,
        (int start, int end)? window = null)
    {
        window ??= DefaultWindow;

        var blockList = blocks.ToList();
        var earliest = blockList.Count > 0
            ? blockList.Select(b => b.Start).Min() / 60 * 60
            : window.Value.start;
        var latest = blockList.Count > 0
            ? (int)Math.Ceiling((double)blockList.Select(b => b.End).Max() / 60) * 60
            : window.Value.end;

        return (
            Math.Min(window.Value.start, earliest),
            Math.Max(window.Value.end, latest)
        );
    }
}

/// <summary>
/// Side-by-side placement for blocks that share a time slot. Without this, a
/// class and a calendar event at the same hour draw on top of each other and
/// the one underneath is simply invisible.
/// </summary>
public static class BlockLayout
{
    public record Placement(DayBlock Block, int Lane, int Lanes)
    {
        public string Id => Block.Id;
    }

    /// <summary>
    /// Blocks are grouped into clusters of transitively-overlapping blocks, so
    /// width is divided only among things that actually collide — one busy
    /// afternoon doesn't shrink the whole day.
    /// </summary>
    public static List<Placement> Arrange(IEnumerable<DayBlock> blocks)
    {
        var sorted = blocks.OrderBy(b => (b.Start, b.End, b.Id)).ToList();
        var placements = new List<Placement>();

        var cluster = new List<(DayBlock block, int lane)>();
        var laneEnds = new List<int>();
        var clusterEnd = int.MinValue;

        void Flush()
        {
            var lanes = Math.Max(laneEnds.Count, 1);
            foreach (var (block, lane) in cluster)
            {
                placements.Add(new Placement(block, lane, lanes));
            }
            cluster.Clear();
            laneEnds.Clear();
            clusterEnd = int.MinValue;
        }

        foreach (var block in sorted)
        {
            // Touching edges aren't an overlap: a 3–6pm and a 6–9pm class are
            // consecutive, and splitting them in half would be wrong.
            if (block.Start >= clusterEnd)
            {
                Flush();
            }

            var lane = laneEnds.FindIndex(end => end <= block.Start);
            if (lane == -1)
                lane = laneEnds.Count;

            if (lane == laneEnds.Count)
            {
                laneEnds.Add(block.End);
            }
            else
            {
                laneEnds[lane] = block.End;
            }

            cluster.Add((block, lane));
            clusterEnd = Math.Max(clusterEnd, block.End);
        }
        Flush();

        return placements;
    }
}
