using Xunit;
using System;
using System.Collections.Generic;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Grades persistence. Tests the round-trip JSON serialization and the
/// cross-platform layer. The Windows ACL itself can't be exercised on non-Windows
/// platforms, so it's verified manually on Windows only.
/// </summary>
public class GradesStoreTests : IDisposable
{
    private readonly string _testDir;

    public GradesStoreTests()
    {
        // Create a unique temp directory for this test
        _testDir = Path.Combine(Path.GetTempPath(), $"GradesStoreTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(_testDir);
        // Override the store to use our test directory
        GradesStore.SetTestDirectory(_testDir);
    }

    public void Dispose()
    {
        // Reset to default directory
        GradesStore.SetTestDirectory(null);
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }
    [Fact]
    public void SaveAndLoadHistoryRoundTrip()
    {
        try
        {
            var reports = new List<GradeReport>
            {
                new GradeReport
                {
                    LastUpdated = new DateTime(2026, 1, 15, 0, 0, 0, DateTimeKind.Utc),
                    Subjects = new List<SubjectGrade>
                    {
                        new SubjectGrade
                        {
                            SubjectCode = "MATH 30083",
                            Description = "Calculus I",
                            Faculty = "TORRES, MARIA",
                            Units = 4.0,
                            SectionCode = "A",
                            FinalGrade = "1.75",
                            GradeStatus = "OK"
                        }
                    },
                    Summary = new Dictionary<string, string> { { "GPA", "3.5" } },
                    SchoolYear = "2024-2025",
                    Semester = "2nd Semester"
                },
                new GradeReport
                {
                    LastUpdated = new DateTime(2026, 8, 13, 0, 0, 0, DateTimeKind.Utc),
                    Subjects = new List<SubjectGrade>
                    {
                        new SubjectGrade
                        {
                            SubjectCode = "COMP 20073",
                            Description = "Data Structures",
                            Faculty = "SANTOS, JUAN",
                            Units = 3.0,
                            SectionCode = "D",
                            FinalGrade = "1.25",
                            GradeStatus = "OK"
                        }
                    },
                    Summary = new Dictionary<string, string> { { "GPA", "4.0" } },
                    SchoolYear = "2025-2026",
                    Semester = "1st Semester"
                }
            };

            GradesStore.SaveHistory(reports);
            var loaded = GradesStore.LoadHistory();

            Assert.Equal(2, loaded.Count);
            Assert.Equal("MATH 30083", loaded[0].Subjects[0].SubjectCode);
            Assert.Equal("COMP 20073", loaded[1].Subjects[0].SubjectCode);
        }
        finally
        {
            GradesStore.Delete();
        }
    }

    [Fact]
    public void MissingFileLoadsAsNull()
    {
        GradesStore.Delete();
        var loaded = GradesStore.Load();
        Assert.Null(loaded);
    }

    [Fact]
    public void MissingHistoryLoadsAsEmptyList()
    {
        GradesStore.Delete();
        var loaded = GradesStore.LoadHistory();
        Assert.Empty(loaded);
    }

    [Fact]
    public void DeleteRemovesCurrentAndHistory()
    {
        var report = new GradeReport
        {
            LastUpdated = DateTime.UtcNow,
            Subjects = new List<SubjectGrade>(),
            Summary = new Dictionary<string, string>()
        };

        GradesStore.Save(report);
        GradesStore.SaveHistory(new List<GradeReport> { report });

        Assert.NotNull(GradesStore.Load());
        Assert.NotEmpty(GradesStore.LoadHistory());

        GradesStore.Delete();

        Assert.Null(GradesStore.Load());
        Assert.Empty(GradesStore.LoadHistory());
    }

    [Fact]
    public void MergedUpdatesHistoryCorrectly()
    {
        var term1 = new GradeReport
        {
            LastUpdated = new DateTime(2026, 1, 15, 0, 0, 0, DateTimeKind.Utc),
            Subjects = new List<SubjectGrade>(),
            Summary = new Dictionary<string, string>(),
            SchoolYear = "2024-2025",
            Semester = "1st Semester"
        };

        var term2 = new GradeReport
        {
            LastUpdated = new DateTime(2026, 8, 13, 0, 0, 0, DateTimeKind.Utc),
            Subjects = new List<SubjectGrade>(),
            Summary = new Dictionary<string, string>(),
            SchoolYear = "2025-2026",
            Semester = "1st Semester"
        };

        var term1_updated = new GradeReport
        {
            LastUpdated = new DateTime(2026, 8, 15, 0, 0, 0, DateTimeKind.Utc),
            Subjects = new List<SubjectGrade>(),
            Summary = new Dictionary<string, string>(),
            SchoolYear = "2024-2025",
            Semester = "1st Semester"
        };

        var history = new List<GradeReport> { term1, term2 };
        var merged = GradesStore.Merged(term1_updated, history);

        // Should have 2 terms, with term1 updated
        Assert.Equal(2, merged.Count);
        Assert.True(merged[0].LastUpdated > term1.LastUpdated);
        Assert.Equal("2024-2025", merged[0].SchoolYear);
    }
}
