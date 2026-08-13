namespace PUPSISPortal.Core.Tests;

public class GridGeometryTests
{
    /// <summary>
    /// 7 columns of 100pt with 5pt gaps = 730pt wide. 960pt tall over a
    /// 16-hour axis is one point per minute, which keeps the arithmetic here
    /// readable.
    /// </summary>
    private readonly GridGeometry _grid = new(
        width: 730,
        height: 960,
        axis: (start: 6 * 60, end: 22 * 60),
        columnSpacing: 5
    );

    [Fact]
    public void TestColumnsDivideTheWidthEvenly()
    {
        Assert.Equal(100, _grid.ColumnWidth, precision: 3);
    }

    [Fact]
    public void TestEachDayStartsWhereTheLastColumnEnded()
    {
        Assert.Equal(0, _grid.X(Weekday.Monday), precision: 3);
        Assert.Equal(105, _grid.X(Weekday.Tuesday), precision: 3);
        Assert.Equal(630, _grid.X(Weekday.Sunday), precision: 3);
    }

    [Fact]
    public void TestAPointResolvesToItsOwnColumn()
    {
        Assert.Equal(Weekday.Monday, _grid.Day(0));
        Assert.Equal(Weekday.Monday, _grid.Day(50));
        Assert.Equal(Weekday.Tuesday, _grid.Day(110));
        Assert.Equal(Weekday.Sunday, _grid.Day(680));
    }

    /// <summary>
    /// Dragging off either edge should keep selecting the end column rather
    /// than falling off the grid.
    /// </summary>
    [Fact]
    public void TestPointsOutsideTheGridClampToTheEndColumns()
    {
        Assert.Equal(Weekday.Monday, _grid.Day(-500));
        Assert.Equal(Weekday.Sunday, _grid.Day(5000));
    }

    [Fact]
    public void TestAZeroWidthGridDoesNotDivideByZero()
    {
        var empty = new GridGeometry(width: 0, height: 0, axis: (start: 0, end: 60));
        Assert.Equal(Weekday.Monday, empty.Day(40));
    }

    // MARK: Drag ranges

    [Fact]
    public void TestASingleColumnDragCoversOneDay()
    {
        var range = _grid.Drag(originX: 40, originY: 480, currentX: 60, currentY: 600);

        Assert.Single(range.Days, Weekday.Monday);
        Assert.False(range.IsMultiDay);
        Assert.Equal(14 * 60, range.Start);
        Assert.Equal(16 * 60, range.End);
    }

    [Fact]
    public void TestDraggingRightCoversEveryColumnBetween()
    {
        var range = _grid.Drag(originX: 40, originY: 480, currentX: 260, currentY: 600);

        Assert.Equal(new[] { Weekday.Monday, Weekday.Tuesday, Weekday.Wednesday }, range.Days);
        Assert.True(range.IsMultiDay);
    }

    /// <summary>
    /// Dragging right-to-left has to mean the same days as left-to-right.
    /// </summary>
    [Fact]
    public void TestDraggingLeftCoversTheSameDays()
    {
        var rightward = _grid.Drag(originX: 40, originY: 480, currentX: 260, currentY: 600);
        var leftward = _grid.Drag(originX: 260, originY: 600, currentX: 40, currentY: 480);

        Assert.Equal(leftward.Days, rightward.Days);
        Assert.Equal(leftward.Start, rightward.Start);
        Assert.Equal(leftward.End, rightward.End);
    }

    /// <summary>
    /// The event is stored starting on the first day; the rest come from the
    /// recurrence rule, so the anchor must be the earliest weekday.
    /// </summary>
    [Fact]
    public void TestTheAnchorDayIsTheEarliestRegardlessOfDragDirection()
    {
        var leftward = _grid.Drag(originX: 470, originY: 480, currentX: 40, currentY: 600);

        Assert.Equal(Weekday.Monday, leftward.AnchorDay);
    }

    [Fact]
    public void TestDragsAcrossTheWholeWeekCoverAllSevenDays()
    {
        var range = _grid.Drag(originX: 0, originY: 0, currentX: 730, currentY: 960);

        var allDays = new[] { Weekday.Monday, Weekday.Tuesday, Weekday.Wednesday,
                              Weekday.Thursday, Weekday.Friday, Weekday.Saturday, Weekday.Sunday };
        Assert.Equal(allDays, range.Days);
    }

    // MARK: Rects

    [Fact]
    public void TestABlockRectMatchesItsColumnAndTimes()
    {
        var rect = _grid.Rect(Weekday.Tuesday, 14 * 60, 16 * 60);

        Assert.Equal(105, rect.MinX, precision: 3);
        Assert.Equal(100, rect.Width, precision: 3);
        Assert.Equal(480, rect.MinY, precision: 3);
        Assert.Equal(120, rect.Height, precision: 3);
    }

    /// <summary>
    /// A zero-length block would give the editor popover nothing to anchor to.
    /// </summary>
    [Fact]
    public void TestAZeroLengthBlockStillHasHeight()
    {
        var rect = _grid.Rect(Weekday.Monday, 9 * 60, 9 * 60);

        Assert.True(rect.Height > 0);
    }

    [Fact]
    public void TestRubberBandCoversTheColumnsItTouches()
    {
        var band = new GridRect(60, 100, 200, 300);

        var days = _grid.Days(band);
        Assert.Equal(new[] { Weekday.Monday, Weekday.Tuesday, Weekday.Wednesday }, days);
    }
}
