using Xunit;
using System;
using System.Collections.Generic;

namespace PUPSISPortal.Core.Tests;

public class JsonStoreTests : IDisposable
{
    private readonly string _testDir;

    public JsonStoreTests()
    {
        _testDir = Path.Combine(Path.GetTempPath(), $"JsonStoreTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(_testDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }

    [Fact]
    public void SaveAndLoadRoundTrip()
    {
        var data = new Dictionary<string, string>
        {
            { "key1", "value1" },
            { "key2", "value2" }
        };

        var result = JsonStore.Save(data, "test.json", _testDir);
        Assert.True(result, "Save should succeed");

        var loaded = JsonStore.Load<Dictionary<string, string>>("test.json", _testDir);
        Assert.NotNull(loaded);
        Assert.Equal(data, loaded);
    }

    [Fact]
    public void LoadMissingFileReturnsNull()
    {
        var loaded = JsonStore.Load<Dictionary<string, string>>("nonexistent.json", _testDir);
        Assert.Null(loaded);
    }

    [Fact]
    public void DeleteRemovesFile()
    {
        var data = new Dictionary<string, string> { { "key", "value" } };
        JsonStore.Save(data, "test.json", _testDir);

        var result = JsonStore.Delete("test.json", _testDir);
        Assert.True(result);

        var loaded = JsonStore.Load<Dictionary<string, string>>("test.json", _testDir);
        Assert.Null(loaded);
    }
}
