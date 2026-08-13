using Xunit;
using System;
using System.Collections.Generic;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Notes persistence. Points the store at a temp directory so nothing touches the
/// real LocalAppData notes.
/// </summary>
public class NotesStoreTests : IDisposable
{
    private readonly string _testDir;
    private const string TestFileName = "notes.json";

    public NotesStoreTests()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"NotesStoreTests-{Guid.NewGuid()}"
        );
        Directory.CreateDirectory(_testDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }

    [Fact]
    public void SetAndGet()
    {
        var store = new NotesStore(TestFileName, _testDir);
        store.SetText("bring calculator", "class:MATH");

        Assert.Equal("bring calculator", store.Text("class:MATH"));
        Assert.True(store.HasNote("class:MATH"));
        Assert.False(store.HasNote("class:PHYS"));
    }

    [Fact]
    public void TitleIsStoredAndPreservedAcrossNilEdits()
    {
        var store = new NotesStore(TestFileName, _testDir);
        store.SetText("draft", "class:MATH", title: "MATH 101");
        Assert.Equal("MATH 101", store.Note("class:MATH")?.Title);

        store.SetText("draft 2", "class:MATH"); // no title passed
        Assert.Equal("MATH 101", store.Note("class:MATH")?.Title);

        // Survives a reload from disk
        var reloaded = new NotesStore(TestFileName, _testDir);
        Assert.Equal("MATH 101", reloaded.Note("class:MATH")?.Title);
    }

    [Fact]
    public void VaultCreateNestAndPersist()
    {
        var store = new NotesStore(TestFileName, _testDir);
        var folder = store.AddFolder("Math", null);
        var fileKey = store.AddFile("Limits", folder);
        store.SetText("lim x->0", fileKey, title: "Limits");

        // Tree shape
        Assert.Single(store.Vault);
        Assert.Equal("Math", store.Vault[0].Name);
        Assert.NotNull(store.Vault[0].Children);
        Assert.Single(store.Vault[0].Children);
        Assert.Equal(fileKey, store.Vault[0].Children[0].NoteKey);
        Assert.Equal("Limits", store.VaultName(fileKey));

        // Reloads from disk with the same tree and text
        var reloaded = new NotesStore(TestFileName, _testDir);
        Assert.Single(reloaded.Vault);
        Assert.Equal("Limits", reloaded.Vault[0].Children?[0].Name);
        Assert.Equal("lim x->0", reloaded.Text(fileKey));

        // Deleting the folder removes the subtree and its notes
        reloaded.DeleteItem(folder);
        Assert.Empty(reloaded.Vault);
        Assert.Equal("", reloaded.Text(fileKey));
    }

    [Fact]
    public void MoveFileBetweenFoldersAndRejectCycles()
    {
        var store = new NotesStore(TestFileName, _testDir);
        var a = store.AddFolder("A", null);
        var b = store.AddFolder("B", null);
        var fileKey = store.AddFile("note", a);
        var fileId = store.Vault.First(v => v.Id == a).Children?[0].Id;

        Assert.NotNull(fileId);

        // Move the file from A into B
        store.Move(fileId.Value, b);
        Assert.Empty(store.Vault.First(v => v.Id == a).Children ?? new List<VaultNode>());
        Assert.Equal(fileKey, store.Vault.First(v => v.Id == b).Children?[0].NoteKey);

        // Moving a folder into its own descendant is rejected (no detach/loss)
        var child = store.AddFolder("child", a);
        store.Move(a, child);
        Assert.NotNull(store.Vault.FirstOrDefault(v => v.Id == a));
        Assert.NotNull(store.Vault.First(v => v.Id == a).Children?.FirstOrDefault(c => c.Id == child));
    }

    [Fact]
    public void LegacyBareDictStillLoads()
    {
        // Pre-vault notes.json is a bare Dictionary[string, Note]
        var legacy = new Dictionary<string, Note>
        {
            { "day:2026-08-08", new Note { Text = "old", Updated = DateTime.UtcNow, Title = null } }
        };

        var json = System.Text.Json.JsonSerializer.Serialize(legacy);
        var path = Path.Combine(_testDir, TestFileName);
        File.WriteAllText(path, json);

        var store = new NotesStore(TestFileName, _testDir);
        Assert.Equal("old", store.Text("day:2026-08-08"));
        Assert.Empty(store.Vault);
    }

    [Fact]
    public void EmptyTextDeletesTheNote()
    {
        var store = new NotesStore(TestFileName, _testDir);
        store.SetText("temp", "day:2026-08-08");
        store.SetText("   \n ", "day:2026-08-08");

        Assert.False(store.HasNote("day:2026-08-08"));
        Assert.Null(store.Note("day:2026-08-08"));
        Assert.Equal("", store.Text("day:2026-08-08"));
    }

    [Fact]
    public void WhitespaceIsNotANote()
    {
        var store = new NotesStore(TestFileName, _testDir);
        store.SetText("   ", "class:CS");
        Assert.False(store.HasNote("class:CS"));
    }

    [Fact]
    public void PersistsAcrossInstances()
    {
        var first = new NotesStore(TestFileName, _testDir);
        first.SetText("study group at 3", "event:evt-123");

        var second = new NotesStore(TestFileName, _testDir);
        Assert.Equal("study group at 3", second.Text("event:evt-123"));
    }

    [Fact]
    public void MissingFileLoadsEmpty()
    {
        var store = new NotesStore(TestFileName, _testDir);
        Assert.Empty(store.Notes);
    }
}
