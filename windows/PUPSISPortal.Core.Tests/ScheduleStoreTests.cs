using Xunit;
using System;
using System.Collections.Generic;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Schedule persistence. Everything here writes to a temp directory — never
/// the real LocalAppData path, which holds the user's actual schedule.
/// </summary>
public class ScheduleStoreTests : IDisposable
{
    private readonly string _testDir;

    public ScheduleStoreTests()
    {
        // Create a unique temp directory for this test
        _testDir = Path.Combine(Path.GetTempPath(), $"ScheduleStoreTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(_testDir);
        // Override the store to use our test directory
        ScheduleStore.SetTestDirectory(_testDir);
    }

    public void Dispose()
    {
        // Reset to default directory
        ScheduleStore.SetTestDirectory(null);
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }

    private readonly List<ClassSession> _fixture = new()
    {
        new ClassSession
        {
            SubjectCode = "COMP 20073",
            Description = "Data Structures",
            Faculty = "SANTOS, JUAN",
            Day = Weekday.Tuesday,
            Start = 14 * 60,
            End = 16 * 60
        },
        new ClassSession
        {
            SubjectCode = "COMP 20073",
            Description = "Data Structures",
            Faculty = "SANTOS, JUAN",
            Day = Weekday.Friday,
            Start = 13 * 60 + 30,
            End = 16 * 60 + 30
        }
    };

    [Fact]
    public void RoundTripsSessionsAndTimestamp()
    {
        var stamp = new DateTime(2025, 8, 6, 0, 0, 0, DateTimeKind.Utc);
        ScheduleStore.Save(_fixture, stamp);

        var loaded = ScheduleStore.Load();
        Assert.NotNull(loaded);
        Assert.Equal(_fixture, loaded.Sessions);
        // DateTime comparison with tolerance for serialization precision
        Assert.Equal(stamp.Ticks, loaded.LastUpdated.Ticks, tolerance: 1_000_000); // ~100ms tolerance
    }

    [Fact]
    public void RoundTripKeepsEveryField()
    {
        ScheduleStore.Save(_fixture);
        var loaded = ScheduleStore.Load();

        Assert.NotNull(loaded);
        var session = loaded.Sessions.First();
        Assert.Equal("COMP 20073", session.SubjectCode);
        Assert.Equal("Data Structures", session.Description);
        Assert.Equal("SANTOS, JUAN", session.Faculty);
        Assert.Equal(Weekday.Tuesday, session.Day);
        Assert.Equal(14 * 60, session.Start);
        Assert.Equal(16 * 60, session.End);
    }

    [Fact]
    public void MissingFileLoadsAsNoCacheRatherThanCrashing()
    {
        var loaded = ScheduleStore.Load();
        Assert.Null(loaded);
    }

    [Fact]
    public void CorruptFileLoadsAsNoCache()
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PUPSISPortal",
            "schedule.json"
        );
        var dir = Path.GetDirectoryName(path);
        if (dir != null && !Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        File.WriteAllText(path, "not json");
        try
        {
            var loaded = ScheduleStore.Load();
            Assert.Null(loaded);
        }
        finally
        {
            if (File.Exists(path))
                File.Delete(path);
        }
    }

    [Fact]
    public void DeleteRemovesTheFile()
    {
        ScheduleStore.Save(_fixture);
        Assert.NotNull(ScheduleStore.Load());

        ScheduleStore.Delete();
        Assert.Null(ScheduleStore.Load());
    }

    [Fact]
    public void IdentityIsStableAcrossDecodes()
    {
        ScheduleStore.Save(_fixture);
        var first = ScheduleStore.Load()?.Sessions.Select(s => s.Id).ToList();
        var second = ScheduleStore.Load()?.Sessions.Select(s => s.Id).ToList();

        Assert.NotNull(first);
        Assert.NotNull(second);
        Assert.Equal(first, second);
    }
}
