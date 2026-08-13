namespace PUPSISPortal.Core;

/// <summary>
/// Everything the Grades page yields: the per-subject rows plus the free-form
/// summary block (Admission Status, Scholastic Status, GPA as SIS prints it).
/// </summary>
public record GradeReport
{
    public required DateTime LastUpdated { get; init; }
    public required List<SubjectGrade> Subjects { get; init; }

    /// <summary>
    /// The &lt;dl&gt; summary as label → value. Stored raw so an unrecognised key
    /// on the live page still round-trips instead of being dropped.
    /// </summary>
    public required Dictionary<string, string> Summary { get; init; }

    /// <summary>
    /// Which term this snapshot is, read from the grades page's School Year /
    /// Semester dropdowns. Optional so a report cached before history existed
    /// (no term fields) still decodes — it just reads as an untagged term.
    /// </summary>
    public string? SchoolYear { get; set; }

    public string? Semester { get; set; }

    /// <summary>
    /// Our own weighted GPA over the posted subjects — the number SIS shows one
    /// term at a time but never breaks down. null when nothing is posted yet,
    /// which reads as "no GPA" rather than a misleading 0.00.
    /// </summary>
    public double? ComputedGpa => GradesParser.Gpa(Subjects);

    public bool HasPostedGrades => Subjects.Any(s => s.IsPosted);

    /// <summary>
    /// Units the student has actually earned this term — posted subjects only,
    /// so unposted and INC/DRP don't inflate the count.
    /// </summary>
    public double CompletedUnits => Subjects
        .Where(s => s.IsPosted)
        .Aggregate(0.0, (sum, s) => sum + s.Units);

    /// <summary>
    /// A short, stable label for the term. Falls back to the update date for a
    /// legacy untagged snapshot so it still reads as *something*.
    /// </summary>
    public string TermLabel
    {
        get
        {
            if (!string.IsNullOrEmpty(SchoolYear) && !string.IsNullOrEmpty(Semester))
                return $"{ShortSemester(Semester)} {SchoolYear}";
            if (!string.IsNullOrEmpty(SchoolYear))
                return SchoolYear;
            if (!string.IsNullOrEmpty(Semester))
                return Semester;
            return LastUpdated.ToString("MMMM yyyy");
        }
    }

    /// <summary>
    /// Chronological sort key: startYear * 10 + semester rank, so terms line
    /// up oldest-first on the trend regardless of scrape order.
    /// ponytail: string heuristic on the dropdown label — fine for PUP's fixed
    /// term names ("2025-2026", "1st Semester", "Summer"); revisit only if the
    /// site changes how it prints them.
    /// </summary>
    public int TermOrder
    {
        get
        {
            var year = StartYear(SchoolYear) ?? 0;
            return year * 10 + SemesterRank(Semester);
        }
    }

    /// <summary>
    /// "2025-2026" → 2025; extract the first run of digits.
    /// </summary>
    private static int? StartYear(string? schoolYear)
    {
        if (string.IsNullOrEmpty(schoolYear))
            return null;

        var digits = new string(schoolYear.TakeWhile(char.IsDigit).ToArray());
        return string.IsNullOrEmpty(digits) ? null : int.TryParse(digits, out var year) ? year : null;
    }

    private static int SemesterRank(string? semester)
    {
        if (string.IsNullOrEmpty(semester))
            return 0;

        var s = semester.ToLowerInvariant();
        if (s.Contains("1st") || s.Contains("first")) return 1;
        if (s.Contains("2nd") || s.Contains("second")) return 2;
        // Summer / midyear sits after both regular semesters.
        if (s.Contains("summer") || s.Contains("mid")) return 3;
        return 0;
    }

    private static string ShortSemester(string semester)
    {
        var s = semester.ToLowerInvariant();
        if (s.Contains("1st") || s.Contains("first")) return "1st Sem";
        if (s.Contains("2nd") || s.Contains("second")) return "2nd Sem";
        if (s.Contains("summer") || s.Contains("mid")) return "Summer";
        return semester;
    }
}
