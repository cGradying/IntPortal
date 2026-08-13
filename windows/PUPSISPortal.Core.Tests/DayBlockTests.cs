using Xunit;

namespace PUPSISPortal.Core.Tests;

public class BlockLayoutTests
{
    private DayBlock Block(string id, int start, int end)
    {
        return new DayBlock(id, Weekday.Monday, start, end, id, "");
    }

    private (int lane, int lanes)? Lanes(IEnumerable<BlockLayout.Placement> placements, string id)
    {
        var placement = placements.FirstOrDefault(p => p.Block.Title == id);
        return placement != null ? (placement.Lane, placement.Lanes) : null;
    }

    [Fact]
    public void TestEmptyDayPlacesNothing()
    {
        Assert.Empty(BlockLayout.Arrange(new List<DayBlock>()));
    }

    [Fact]
    public void TestASingleBlockTakesTheFullWidth()
    {
        var placements = BlockLayout.Arrange(new[] { Block("a", 540, 660) });

        Assert.Single(placements);
        Assert.Equal(1, Lanes(placements, "a")?.lanes);
        Assert.Equal(0, Lanes(placements, "a")?.lane);
    }

    /// <summary>
    /// The whole reason this exists: two blocks at the same hour must not draw
    /// on top of each other.
    /// </summary>
    [Fact]
    public void TestOverlappingBlocksSplitTheWidth()
    {
        var placements = BlockLayout.Arrange(new[] { Block("a", 540, 660), Block("b", 600, 720) });

        Assert.Equal(2, Lanes(placements, "a")?.lanes);
        Assert.Equal(2, Lanes(placements, "b")?.lanes);
        Assert.NotEqual(Lanes(placements, "a")?.lane, Lanes(placements, "b")?.lane);
    }

    /// <summary>
    /// 3–6pm followed by 6–9pm is consecutive, not concurrent. Treating a
    /// shared edge as an overlap would halve two classes that never collide.
    /// </summary>
    [Fact]
    public void TestTouchingEdgesAreNotAnOverlap()
    {
        var placements = BlockLayout.Arrange(new[] { Block("a", 900, 1080), Block("b", 1080, 1260) });

        Assert.Equal(1, Lanes(placements, "a")?.lanes);
        Assert.Equal(1, Lanes(placements, "b")?.lanes);
    }

    /// <summary>
    /// A busy morning must not shrink an unrelated afternoon block.
    /// </summary>
    [Fact]
    public void TestSeparateClustersAreSizedIndependently()
    {
        var placements = BlockLayout.Arrange(new[]
        {
            Block("morningA", 480, 600),
            Block("morningB", 540, 660),
            Block("afternoon", 840, 960),
        });

        Assert.Equal(2, Lanes(placements, "morningA")?.lanes);
        Assert.Equal(1, Lanes(placements, "afternoon")?.lanes);
    }

    /// <summary>
    /// Three-way pileup, and the third block reuses the lane the first freed.
    /// </summary>
    [Fact]
    public void TestLanesAreReusedOnceABlockHasEnded()
    {
        var placements = BlockLayout.Arrange(new[]
        {
            Block("a", 480, 540),
            Block("b", 500, 700),
            Block("c", 560, 620),
        });

        // a and b overlap, c overlaps b but starts after a ends.
        Assert.Equal(2, Lanes(placements, "b")?.lanes);
        Assert.Equal(0, Lanes(placements, "a")?.lane);
        Assert.Equal(0, Lanes(placements, "c")?.lane);
        Assert.Equal(1, Lanes(placements, "b")?.lane);
    }

    [Fact]
    public void TestEveryBlockIsPlacedExactlyOnce()
    {
        var input = new[] { Block("a", 480, 600), Block("b", 540, 660), Block("c", 900, 960) };

        var placements = BlockLayout.Arrange(input);

        Assert.Equal(input.Length, placements.Count);
        Assert.Equal(
            new HashSet<string>(input.Select(b => b.Id)),
            new HashSet<string>(placements.Select(p => p.Block.Id))
        );
    }
}

public class BlockRunsTests
{
    private DayBlock Event(string title, Weekday day, int start = 840, int end = 960)
    {
        return new DayBlock(
            id: $"{title}-{(int)day}",
            day: day,
            start: start,
            end: end,
            title: title,
            subtitle: "",
            groupKey: $"event-{title}-{start}-{end}"
        );
    }

    private DayBlock Session(string code, Weekday day, int start = 840, int end = 960)
    {
        return new DayBlock(new ClassSession
        {
            SubjectCode = code,
            Description = "",
            Faculty = "SANTOS, JUAN",
            Day = day,
            Start = start,
            End = end
        });
    }

    [Fact]
    public void TestALoneBlockIsItsOwnRun()
    {
        var block = Event("Study", Weekday.Wednesday);

        var positions = BlockRuns.Positions(new[] { block });
        Assert.Equal(RunPosition.Single, positions[block.Id]);
    }

    /// <summary>
    /// The case that prompted this: a drag from Monday to Wednesday drew three
    /// unconnected boxes.
    /// </summary>
    [Fact]
    public void TestConsecutiveDaysFormOneRun()
    {
        var blocks = new[]
        {
            Event("Study", Weekday.Monday),
            Event("Study", Weekday.Tuesday),
            Event("Study", Weekday.Wednesday)
        };

        var positions = BlockRuns.Positions(blocks);

        Assert.Equal(RunPosition.Leading, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Middle, positions[blocks[1].Id]);
        Assert.Equal(RunPosition.Trailing, positions[blocks[2].Id]);
    }

    [Fact]
    public void TestATwoDayRunHasNoMiddle()
    {
        var blocks = new[]
        {
            Event("Study", Weekday.Thursday),
            Event("Study", Weekday.Friday)
        };
        var positions = BlockRuns.Positions(blocks);

        Assert.Equal(RunPosition.Leading, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Trailing, positions[blocks[1].Id]);
    }

    /// <summary>
    /// Bridging Monday to Wednesday would draw a bar straight through a
    /// Tuesday the class doesn't meet on.
    /// </summary>
    [Fact]
    public void TestNonConsecutiveDaysDoNotJoin()
    {
        var blocks = new[]
        {
            Session("COMP 001", Weekday.Monday),
            Session("COMP 001", Weekday.Wednesday),
            Session("COMP 001", Weekday.Friday)
        };

        var positions = BlockRuns.Positions(blocks);
        foreach (var block in blocks)
        {
            Assert.Equal(RunPosition.Single, positions[block.Id]);
        }
    }

    /// <summary>
    /// Two subjects at the same hour on adjacent days are unrelated.
    /// </summary>
    [Fact]
    public void TestDifferentThingsNeverJoin()
    {
        var blocks = new[]
        {
            Session("COMP 001", Weekday.Monday),
            Session("GEED 005", Weekday.Tuesday)
        };

        var positions = BlockRuns.Positions(blocks);
        Assert.Equal(RunPosition.Single, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Single, positions[blocks[1].Id]);
    }

    /// <summary>
    /// Same subject, different hour — a run means the same slot across days.
    /// </summary>
    [Fact]
    public void TestTheSameSubjectAtADifferentHourIsADifferentRun()
    {
        var blocks = new[]
        {
            Session("COMP 001", Weekday.Monday, 480, 600),
            Session("COMP 001", Weekday.Tuesday, 840, 960)
        };

        var positions = BlockRuns.Positions(blocks);
        Assert.Equal(RunPosition.Single, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Single, positions[blocks[1].Id]);
    }

    /// <summary>
    /// Two runs of the same thing in one week each get their own ends.
    /// </summary>
    [Fact]
    public void TestAGapSplitsOneGroupIntoTwoRuns()
    {
        var blocks = new[]
        {
            Event("Study", Weekday.Monday),
            Event("Study", Weekday.Tuesday),
            Event("Study", Weekday.Thursday),
            Event("Study", Weekday.Friday)
        };
        var positions = BlockRuns.Positions(blocks);

        Assert.Equal(RunPosition.Leading, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Trailing, positions[blocks[1].Id]);
        Assert.Equal(RunPosition.Leading, positions[blocks[2].Id]);
        Assert.Equal(RunPosition.Trailing, positions[blocks[3].Id]);
    }

    /// <summary>
    /// Sunday closes the week. Joining it to Monday would draw a bar off the
    /// right edge of the grid and back in on the left.
    /// </summary>
    [Fact]
    public void TestTheWeekDoesNotWrapFromSundayToMonday()
    {
        var blocks = new[]
        {
            Event("Study", Weekday.Sunday),
            Event("Study", Weekday.Monday)
        };
        var positions = BlockRuns.Positions(blocks);

        Assert.Equal(RunPosition.Single, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Single, positions[blocks[1].Id]);
    }

    /// <summary>
    /// The far end of the week does join normally.
    /// </summary>
    [Fact]
    public void TestSaturdayAndSundayJoin()
    {
        var blocks = new[]
        {
            Event("Study", Weekday.Saturday),
            Event("Study", Weekday.Sunday)
        };
        var positions = BlockRuns.Positions(blocks);

        Assert.Equal(RunPosition.Leading, positions[blocks[0].Id]);
        Assert.Equal(RunPosition.Trailing, positions[blocks[1].Id]);
    }

    /// <summary>
    /// Only the ends round, so the joins read as one continuous bar.
    /// </summary>
    [Fact]
    public void TestOnlyTheOuterCornersOfARunAreRounded()
    {
        Assert.True(RunPosition.Single.RoundsLeft() && RunPosition.Single.RoundsRight());
        Assert.True(RunPosition.Leading.RoundsLeft());
        Assert.False(RunPosition.Leading.RoundsRight());
        Assert.False(RunPosition.Middle.RoundsLeft() || RunPosition.Middle.RoundsRight());
        Assert.True(RunPosition.Trailing.RoundsRight());
    }

    /// <summary>
    /// Everything but the last block reaches across the column gap.
    /// </summary>
    [Fact]
    public void TestOnlyTheLastBlockOfARunStopsAtItsColumn()
    {
        Assert.True(RunPosition.Leading.BridgesRight());
        Assert.True(RunPosition.Middle.BridgesRight());
        Assert.False(RunPosition.Trailing.BridgesRight());
        Assert.False(RunPosition.Single.BridgesRight());
    }
}

public class GridAxisTests
{
    private DayBlock Block(int start, int end)
    {
        return new DayBlock(
            id: $"{start}-{end}",
            day: Weekday.Monday,
            start: start,
            end: end,
            title: "x",
            subtitle: ""
        );
    }

    [Fact]
    public void TestAnEmptyWeekStillShowsTheNormalDay()
    {
        var axis = GridAxis.Hours(new List<DayBlock>());
        Assert.Equal(6 * 60, axis.start);
        Assert.Equal(22 * 60, axis.end);
    }

    /// <summary>
    /// A schedule sitting inside 6am–10pm must not shrink the grid to fit it,
    /// or the layout changes shape every time the timetable does.
    /// </summary>
    [Fact]
    public void TestABusyDayInsideTheWindowDoesNotShrinkIt()
    {
        var axis = GridAxis.Hours(new[] { Block(8 * 60, 10 * 60), Block(13 * 60, 18 * 60) });

        Assert.Equal(6 * 60, axis.start);
        Assert.Equal(22 * 60, axis.end);
    }

    [Fact]
    public void TestAnEarlyClassPushesTheTopOut()
    {
        var axis = GridAxis.Hours(new[] { Block(5 * 60 + 30, 7 * 60) });

        Assert.Equal(5 * 60, axis.start);
        Assert.Equal(22 * 60, axis.end);
    }

    [Fact]
    public void TestALateClassPushesTheBottomOut()
    {
        var axis = GridAxis.Hours(new[] { Block(20 * 60, 22 * 60 + 30) });

        Assert.Equal(6 * 60, axis.start);
        Assert.Equal(23 * 60, axis.end);
    }

    /// <summary>
    /// Both edges at once, and neither may clip its block.
    /// </summary>
    [Fact]
    public void TestTheAxisNeverClipsABlock()
    {
        var blocks = new[] { Block(4 * 60 + 15, 6 * 60), Block(21 * 60, 23 * 60 + 45) };
        var axis = GridAxis.Hours(blocks);

        Assert.True(axis.start <= blocks.Select(b => b.Start).Min());
        Assert.True(axis.end >= blocks.Select(b => b.End).Max());
    }

    /// <summary>
    /// Hour rules and gutter labels are drawn per hour; a ragged edge would
    /// put the first label off the top of the grid.
    /// </summary>
    [Fact]
    public void TestEdgesLandOnWholeHours()
    {
        var axis = GridAxis.Hours(new[] { Block(5 * 60 + 30, 22 * 60 + 1) });

        Assert.Equal(0, axis.start % 60);
        Assert.Equal(0, axis.end % 60);
    }
}

public class DayBlockTests
{
    private readonly ClassSession _session = new()
    {
        SubjectCode = "COMP 20073",
        Description = "Data Structures",
        Faculty = "SANTOS, JUAN",
        Day = Weekday.Tuesday,
        Start = 14 * 60,
        End = 16 * 60
    };

    [Fact]
    public void TestAClassCarriesItsSessionThrough()
    {
        var block = new DayBlock(_session);

        Assert.Equal(Weekday.Tuesday, block.Day);
        Assert.Equal(14 * 60, block.Start);
        Assert.Equal(16 * 60, block.End);
        Assert.Equal("COMP 20073", block.Title);
        Assert.Equal(_session, block.Session);
    }

    /// <summary>
    /// An event has no session — anything reading one back must get null rather
    /// than a stand-in, or event blocks would grow class-only controls.
    /// </summary>
    [Fact]
    public void TestAnEventHasNoSession()
    {
        var block = new DayBlock(
            id: "abc",
            day: Weekday.Monday,
            start: 600,
            end: 660,
            title: "Dentist",
            subtitle: "10AM – 11AM"
        );

        Assert.Null(block.Session);
        Assert.Equal(DayBlock.SourceType.CalendarEvent, block.Source);
    }

    /// <summary>
    /// Ids are namespaced: a class and an event could otherwise collide and
    /// SwiftUI would reuse the wrong view.
    /// </summary>
    [Fact]
    public void TestClassAndEventIdsCannotCollide()
    {
        var classBlock = new DayBlock(_session);
        var eventBlock = new DayBlock(
            id: _session.Id,
            day: Weekday.Tuesday,
            start: 14 * 60,
            end: 16 * 60,
            title: "Decoy",
            subtitle: ""
        );

        Assert.NotEqual(classBlock.Id, eventBlock.Id);
    }
}
