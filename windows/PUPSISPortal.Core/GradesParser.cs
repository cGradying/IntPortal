namespace PUPSISPortal.Core;

/// <summary>
/// Turns scraped grade rows into typed values, and computes the GPA.
/// </summary>
public static class GradesParser
{
    public static List<SubjectGrade> Parse(IEnumerable<Dictionary<string, string>> rows)
    {
        return rows
            .Select(ParseRow)
            .Where(s => s != null)
            .Cast<SubjectGrade>()
            .ToList();
    }

    /// <summary>
    /// A row with no subject code is a spacer or a totals line, not a subject —
    /// skipped, never crashed on.
    /// </summary>
    private static SubjectGrade? ParseRow(Dictionary<string, string> row)
    {
        var code = (row.TryGetValue("subjectCode", out var c) ? c : string.Empty).Trim();
        if (string.IsNullOrEmpty(code))
            return null;

        return new SubjectGrade
        {
            SubjectCode = code,
            Description = (row.TryGetValue("description", out var d) ? d : string.Empty).Trim(),
            Faculty = (row.TryGetValue("faculty", out var f) ? f : string.Empty).Trim(),
            Units = double.TryParse(
                (row.TryGetValue("unit", out var u) ? u : string.Empty).Trim(),
                out var units) ? units : 0,
            SectionCode = (row.TryGetValue("sectionCode", out var s) ? s : string.Empty).Trim(),
            FinalGrade = (row.TryGetValue("finalGrade", out var fg) ? fg : string.Empty).Trim(),
            GradeStatus = (row.TryGetValue("gradeStatus", out var gs) ? gs : string.Empty).Trim()
        };
    }

    /// <summary>
    /// Units-weighted average of the posted numeric grades. Unposted and
    /// non-numeric subjects (INC, DRP) are excluded entirely — they don't drag
    /// the average toward zero, and a subject with zero listed units can't
    /// weight anything.
    /// </summary>
    public static double? Gpa(IEnumerable<SubjectGrade> subjects)
    {
        var posted = subjects
            .Select(s => new { s.NumericGrade, s.Units })
            .Where(x => x.NumericGrade.HasValue && x.Units > 0)
            .ToList();

        if (!posted.Any())
            return null;

        var totalUnits = posted.Sum(x => x.Units);
        if (totalUnits <= 0)
            return null;

        var weighted = posted.Sum(x => x.NumericGrade!.Value * x.Units);
        return Math.Round(weighted / totalUnits * 100) / 100;
    }
}
