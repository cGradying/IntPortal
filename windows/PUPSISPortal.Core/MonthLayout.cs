namespace PUPSISPortal.Core;

/// <summary>
/// Date math for a month grid, kept out of the view so it can be tested.
/// </summary>
public static class MonthLayout
{
    /// <summary>
    /// Always six full weeks, so every month in the year view is the same
    /// height and the grid doesn't reflow as you scroll. Cells outside the
    /// month are real dates from the neighbouring months, drawn faintly.
    ///
    /// Monday-first, matching the week grid. The grid ignores
    /// <see cref="System.Globalization.Calendar.FirstDayOfWeek"/> and always
    /// starts on Monday to stay consistent with the rest of the app.
    /// </summary>
    public static List<DateTime> Days(DateTime date)
    {
        var firstOfMonth = StartOfMonth(date);
        var gridStart = WeekStart(firstOfMonth);

        var result = new List<DateTime>();
        for (int i = 0; i < 42; i++)
        {
            result.Add(gridStart.AddDays(i));
        }
        return result;
    }

    /// <summary>
    /// Midnight at the start of the month containing the given date.
    /// </summary>
    public static DateTime StartOfMonth(DateTime date)
    {
        return new DateTime(date.Year, date.Month, 1);
    }

    /// <summary>
    /// Midnight on the Monday of `date`'s week.
    /// </summary>
    private static DateTime WeekStart(DateTime date)
    {
        return WeekdayExtensions.WeekStart(date);
    }

    /// <summary>
    /// The twelve first-of-month dates for a year.
    /// </summary>
    public static List<DateTime> Months(int year)
    {
        var result = new List<DateTime>();
        for (int month = 1; month <= 12; month++)
        {
            result.Add(new DateTime(year, month, 1));
        }
        return result;
    }

    /// <summary>
    /// Whether two dates fall in the same month.
    /// </summary>
    public static bool IsSameMonth(DateTime date, DateTime other)
    {
        return date.Year == other.Year && date.Month == other.Month;
    }
}
