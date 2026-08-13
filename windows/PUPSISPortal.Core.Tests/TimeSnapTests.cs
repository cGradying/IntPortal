namespace PUPSISPortal.Core.Tests;

public class TimeSnapTests
{
    private readonly (int start, int end) _axis = (start: 6 * 60, end: 22 * 60);

    [Fact]
    public void TestSnappingGoesToTheNearestQuarterHour()
    {
        Assert.Equal(0, TimeSnap.Snap(0));
        Assert.Equal(0, TimeSnap.Snap(7));
        Assert.Equal(15, TimeSnap.Snap(8));
        Assert.Equal(15, TimeSnap.Snap(22));
        Assert.Equal(30, TimeSnap.Snap(23));
    }

    [Fact]
    public void TestTheTopAndBottomOfTheGridMapToTheAxisEdges()
    {
        Assert.Equal(_axis.start, TimeSnap.Minutes(0, _axis, 960));
        Assert.Equal(_axis.end, TimeSnap.Minutes(960, _axis, 960));
    }

    /// <summary>
    /// 960pt over a 16-hour axis is one point per minute, so halfway down is
    /// eight hours in — 2pm.
    /// </summary>
    [Fact]
    public void TestAPointInTheMiddleMapsToTheMiddleOfTheDay()
    {
        Assert.Equal(14 * 60, TimeSnap.Minutes(480, _axis, 960));
    }

    [Fact]
    public void TestDraggingOffTheEndsIsClampedToTheGrid()
    {
        Assert.Equal(_axis.start, TimeSnap.Minutes(-400, _axis, 960));
        Assert.Equal(_axis.end, TimeSnap.Minutes(4000, _axis, 960));
    }

    [Fact]
    public void TestAZeroHeightGridDoesNotDivideByZero()
    {
        Assert.Equal(_axis.start, TimeSnap.Minutes(50, _axis, 0));
    }

    // MARK: Drag ranges

    [Fact]
    public void TestDraggingDownwardsProducesThatRange()
    {
        var range = TimeSnap.Range(9 * 60, 11 * 60, _axis);

        Assert.Equal(9 * 60, range.start);
        Assert.Equal(11 * 60, range.end);
    }

    /// <summary>
    /// Dragging upward has to mean the same thing as dragging downward.
    /// </summary>
    [Fact]
    public void TestDraggingUpwardsProducesTheSameRange()
    {
        var up = TimeSnap.Range(11 * 60, 9 * 60, _axis);
        var down = TimeSnap.Range(9 * 60, 11 * 60, _axis);

        Assert.Equal(up.start, down.start);
        Assert.Equal(up.end, down.end);
    }

    /// <summary>
    /// A click without movement should still create something usable rather
    /// than a zero-length block.
    /// </summary>
    [Fact]
    public void TestAStationaryDragStillMakesAMinimumEvent()
    {
        var range = TimeSnap.Range(9 * 60, 9 * 60, _axis);

        Assert.Equal(TimeSnap.MinimumDuration, range.end - range.start);
    }

    /// <summary>
    /// At the very bottom of the day there's no room to grow downward, so it
    /// has to grow upward instead of producing nothing.
    /// </summary>
    [Fact]
    public void TestAtTheBottomOfTheDayTheMinimumGrowsUpwards()
    {
        var range = TimeSnap.Range(_axis.end, _axis.end, _axis);

        Assert.Equal(_axis.end, range.end);
        Assert.Equal(TimeSnap.MinimumDuration, range.end - range.start);
        Assert.True(range.start >= _axis.start);
    }

    // MARK: Resizing

    [Fact]
    public void TestDraggingTheBottomEdgeMovesOnlyTheEnd()
    {
        var resized = TimeSnap.Resize(9 * 60, 10 * 60, TimeSnap.Edge.Bottom, 12 * 60, _axis);

        Assert.Equal(9 * 60, resized.start);
        Assert.Equal(12 * 60, resized.end);
    }

    [Fact]
    public void TestDraggingTheTopEdgeMovesOnlyTheStart()
    {
        var resized = TimeSnap.Resize(9 * 60, 12 * 60, TimeSnap.Edge.Top, 8 * 60, _axis);

        Assert.Equal(8 * 60, resized.start);
        Assert.Equal(12 * 60, resized.end);
    }

    /// <summary>
    /// Dragging an edge past the opposite one must not invert the block.
    /// </summary>
    [Fact]
    public void TestAnEdgeCannotBeDraggedThroughTheOther()
    {
        var bottom = TimeSnap.Resize(9 * 60, 12 * 60, TimeSnap.Edge.Bottom, 7 * 60, _axis);
        Assert.Equal(TimeSnap.MinimumDuration, bottom.end - bottom.start);

        var top = TimeSnap.Resize(9 * 60, 12 * 60, TimeSnap.Edge.Top, 20 * 60, _axis);
        Assert.Equal(TimeSnap.MinimumDuration, top.end - top.start);
    }

    [Fact]
    public void TestResizingIsClampedToTheGrid()
    {
        var above = TimeSnap.Resize(9 * 60, 12 * 60, TimeSnap.Edge.Top, 0, _axis);
        Assert.Equal(_axis.start, above.start);

        var below = TimeSnap.Resize(9 * 60, 12 * 60, TimeSnap.Edge.Bottom, 30 * 60, _axis);
        Assert.Equal(_axis.end, below.end);
    }
}
