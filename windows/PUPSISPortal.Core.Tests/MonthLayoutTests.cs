namespace PUPSISPortal.Core.Tests;

public class MonthLayoutTests
{
    private static DateTime Date(int year, int month, int day) => new(year, month, day);

    [Fact]
    public void TestAMonthGridIsAlwaysSixFullWeeks()
    {
        for (int month = 1; month <= 12; month++)
        {
            var days = MonthLayout.Days(Date(2026, month, 1));
            Assert.Equal(42, days.Count);
        }
    }

    /// <summary>
    /// January 2026 opens on a Thursday, so the grid has to start on the
    /// Monday of the week before — 29 December 2025.
    /// </summary>
    [Fact]
    public void TestTheGridStartsOnTheMondayOnOrBeforeTheFirst()
    {
        var days = MonthLayout.Days(Date(2026, 1, 15));

        Assert.Equal(Date(2025, 12, 29), days.First());
        Assert.Equal(Weekday.Monday, WeekdayExtensions.On(days.First()));
    }

    /// <summary>
    /// The grid must be Monday-first regardless of system locale.
    /// </summary>
    [Fact]
    public void TestGridIsMondayFirstRegardlessOfLocale()
    {
        for (int month = 1; month <= 12; month++)
        {
            var days = MonthLayout.Days(Date(2026, month, 1));
            var first = days.First();
            Assert.Equal(Weekday.Monday, WeekdayExtensions.On(first));
        }
    }

    [Fact]
    public void TestDaysAreConsecutiveWithNoGaps()
    {
        var days = MonthLayout.Days(Date(2026, 8, 5));

        for (int i = 0; i < days.Count - 1; i++)
        {
            var earlier = days[i];
            var later = days[i + 1];
            var gap = (later - earlier).Days;
            Assert.Equal(1, gap);
        }
    }

    /// <summary>
    /// Padding cells are real neighbouring dates, and have to be drawn faintly
    /// rather than treated as part of the month.
    /// </summary>
    [Fact]
    public void TestPaddingCellsAreMarkedAsOutsideTheMonth()
    {
        var august = Date(2026, 8, 1);
        var days = MonthLayout.Days(august);

        var inMonth = days.Where(d => MonthLayout.IsSameMonth(d, august)).ToList();
        Assert.Equal(31, inMonth.Count);
        Assert.False(MonthLayout.IsSameMonth(days.First(), august));
    }

    [Fact]
    public void TestAYearHasTwelveMonthsInOrder()
    {
        var months = MonthLayout.Months(2026);

        Assert.Equal(12, months.Count);
        var monthNumbers = months.Select(m => m.Month).ToList();
        Assert.Equal(Enumerable.Range(1, 12), monthNumbers);
        var years = months.Select(m => m.Year).Distinct();
        Assert.Single(years, 2026);
    }

    /// <summary>
    /// February 2027 starts on a Monday and has 28 days — exactly four weeks,
    /// the case most likely to produce a short grid.
    /// </summary>
    [Fact]
    public void TestAnExactlyFourWeekMonthStillFillsSixRows()
    {
        var february = Date(2027, 2, 1);
        var days = MonthLayout.Days(february);

        Assert.Equal(Weekday.Monday, WeekdayExtensions.On(february));
        Assert.Equal(42, days.Count);
        Assert.Equal(february, days.First());
    }
}
