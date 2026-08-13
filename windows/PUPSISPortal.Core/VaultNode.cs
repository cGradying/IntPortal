namespace PUPSISPortal.Core;

/// <summary>
/// A node in the user's freeform notes vault: either a folder (with `Children`)
/// or a file (with a `NoteKey` into the notes dict). The tree is user-built —
/// create folders, create named notes, nest them — separate from the
/// schedule-linked notes (class/day/event) which stay keyed automatically.
/// </summary>
public class VaultNode
{
    public Guid Id { get; set; }
    public string Name { get; set; }
    public bool IsFolder { get; set; }
    /// <summary>
    /// Folder contents. null/empty list for files.
    /// </summary>
    public List<VaultNode>? Children { get; set; }
    /// <summary>
    /// The notes-dict key holding this file's text. null for folders.
    /// </summary>
    public string? NoteKey { get; set; }

    public VaultNode()
    {
        Id = Guid.NewGuid();
        Name = "";
        IsFolder = false;
    }

    public VaultNode(Guid id, string name, bool isFolder, List<VaultNode>? children = null, string? noteKey = null)
    {
        Id = id;
        Name = name;
        IsFolder = isFolder;
        Children = children;
        NoteKey = noteKey;
    }

    public override bool Equals(object? obj) => obj is VaultNode node && Id == node.Id;
    public override int GetHashCode() => Id.GetHashCode();
}
