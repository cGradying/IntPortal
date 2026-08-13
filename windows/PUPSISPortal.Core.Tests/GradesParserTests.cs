using PUPSISPortal.Core;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Fixtures use the same fake subjects the rest of the suite does — never a
/// real transcript, name, or student number.
/// </summary>
[System.Runtime.Versioning.SupportedOSPlatform("windows")]
public class GradesParserTests
{
    private Dictionary<string, string> Row(
        string code,
        string units,
        string grade,
        string status = "",
        string section = "1")
    {
        return new Dictionary<string, string>
        {
            { "subjectCode", code },
            { "description", "Test Subject" },
            { "faculty", "SANTOS, JUAN" },
            { "unit", units },
            { "sectionCode", section },
            { "finalGrade", grade },
            { "gradeStatus", status },
        };
    }

    [Fact]
    public void ParsesEveryFieldOfARow()
    {
        var subject = GradesParser.Parse(new[] { Row("COMP 20073", units: "3", grade: "1.75", status: "Passed") })
            .FirstOrDefault();

        Assert.NotNull(subject);
        Assert.Equal("COMP 20073", subject.SubjectCode);
        Assert.Equal(3, subject.Units);
        Assert.Equal("1.75", subject.FinalGrade);
        Assert.Equal("Passed", subject.GradeStatus);
        Assert.True(subject.IsPosted);
    }

    /// <summary>
    /// A blank grade cell is the normal state for most of a semester, not a
    /// parse failure — the subject still lists, just unposted.
    /// </summary>
    [Fact]
    public void AnUnpostedGradeStillListsTheSubject()
    {
        var subject = GradesParser.Parse(new[] { Row("COMP 20073", units: "3", grade: "") })
            .FirstOrDefault();

        Assert.NotNull(subject);
        Assert.Equal("COMP 20073", subject.SubjectCode);
        Assert.False(subject.IsPosted);
        Assert.Null(subject.NumericGrade);
    }

    [Fact]
    public void RowsWithNoSubjectCodeAreSkippedNotCrashed()
    {
        var rows = new[]
        {
            Row("", units: "0", grade: ""),          // spacer / totals line
            Row("COMP 20073", units: "3", grade: "1.00"),
        };
        var subjects = GradesParser.Parse(rows);

        Assert.Single(subjects);
        Assert.Equal("COMP 20073", subjects.First().SubjectCode);
    }

    // MARK: GPA

    /// <summary>
    /// With nothing posted the GPA is absent, not 0.00 — a zero would read as a
    /// perfect-fail average that never happened.
    /// </summary>
    [Fact]
    public void AllUnpostedYieldsNoGPA()
    {
        var subjects = GradesParser.Parse(new[]
        {
            Row("COMP 20073", units: "3", grade: ""),
            Row("GEED 005", units: "3", grade: ""),
        });

        Assert.Null(GradesParser.Gpa(subjects));
        Assert.False(new GradeReport
        {
            LastUpdated = DateTime.Now,
            Subjects = subjects,
            Summary = new Dictionary<string, string>(),
        }.HasPostedGrades);
    }

    /// <summary>
    /// A mix weights only the posted subjects; the unposted one contributes
    /// neither grade nor units.
    /// </summary>
    [Fact]
    public void GPAWeightsOnlyThePostedSubjects()
    {
        var subjects = GradesParser.Parse(new[]
        {
            Row("COMP 20073", units: "3", grade: "1.00"),
            Row("GEED 005", units: "1", grade: "2.00"),
            Row("PATHFIT 1", units: "2", grade: ""),      // unposted — ignored
        });

        // (1.00·3 + 2.00·1) / (3 + 1) = 1.25
        var gpa = GradesParser.Gpa(subjects);
        Assert.NotNull(gpa);
        Assert.Equal(1.25, gpa.Value, precision: 4);
    }

    /// <summary>
    /// A non-numeric mark (INC, DRP) is excluded from the average but must
    /// still appear in the list.
    /// </summary>
    [Fact]
    public void NonNumericMarksAreExcludedFromGPAButStillListed()
    {
        var subjects = GradesParser.Parse(new[]
        {
            Row("COMP 20073", units: "3", grade: "1.50"),
            Row("GEED 005", units: "3", grade: "INC"),
            Row("PATHFIT 1", units: "2", grade: "DRP"),
        });

        Assert.Equal(3, subjects.Count);
        // Only COMP 20073 counts, so its own grade is the average.
        var gpa = GradesParser.Gpa(subjects);
        Assert.NotNull(gpa);
        Assert.Equal(1.50, gpa.Value, precision: 4);
    }

    /// <summary>
    /// A posted grade on a zero-unit subject can't weight anything, so it must
    /// not divide by zero or skew the average.
    /// </summary>
    [Fact]
    public void ZeroUnitSubjectsDoNotBreakTheAverage()
    {
        var subjects = GradesParser.Parse(new[]
        {
            Row("COMP 20073", units: "3", grade: "2.00"),
            Row("NSTP 001", units: "0", grade: "1.00"),
        });

        var gpa = GradesParser.Gpa(subjects);
        Assert.NotNull(gpa);
        Assert.Equal(2.00, gpa.Value, precision: 4);
    }

    /// <summary>
    /// Section code disambiguates a subject taken twice; ids must stay distinct.
    /// </summary>
    [Fact]
    public void SameSubjectDifferentSectionsGetDistinctIDs()
    {
        var subjects = GradesParser.Parse(new[]
        {
            Row("COMP 20073", units: "3", grade: "1.00", section: "1"),
            Row("COMP 20073", units: "3", grade: "2.00", section: "2"),
        });

        var ids = new HashSet<string>(subjects.Select(s => s.Id));
        Assert.Equal(2, ids.Count);
    }
}
