namespace PUPSISPortal.Core;

/// <summary>
/// One subject's grade for a term. <see cref="FinalGrade"/> is empty until the school
/// posts it — which, for most of a semester, is the normal state.
/// </summary>
public record SubjectGrade
{
    public required string SubjectCode { get; init; }
    public required string Description { get; init; }
    public required string Faculty { get; init; }
    public required double Units { get; init; }
    public required string SectionCode { get; init; }

    /// <summary>
    /// As printed: "1.00", "" (not posted yet), or a non-numeric mark like
    /// "INC" / "DRP". Kept as a string because those last three all live here.
    /// </summary>
    public required string FinalGrade { get; init; }

    public required string GradeStatus { get; init; }

    /// <summary>
    /// Section code disambiguates the same subject taken twice; falling back to
    /// the code keeps the id stable when a section isn't listed.
    /// </summary>
    public string Id => string.IsNullOrEmpty(SectionCode)
        ? SubjectCode
        : $"{SubjectCode}-{SectionCode}";

    /// <summary>
    /// The numeric value only when the grade is posted *and* numeric. PUP grades
    /// run 1.00 (best) to 5.00 (fail); "INC", "DRP", and a blank cell all return
    /// null so they never get counted as a zero — which would be the obvious,
    /// wrong way to average them.
    /// </summary>
    public double? NumericGrade
    {
        get
        {
            var trimmed = (FinalGrade ?? string.Empty).Trim();
            return double.TryParse(trimmed, out var grade) ? grade : null;
        }
    }

    public bool IsPosted => NumericGrade.HasValue;
}
