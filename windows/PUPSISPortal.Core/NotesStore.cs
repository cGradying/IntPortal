namespace PUPSISPortal.Core;

/// <summary>
/// Notes the user attaches from the Today screen: one per class or event, plus a
/// freeform per-day scratchpad, plus a user-built vault of folders and files.
/// Keyed by an opaque string the caller chooses (subject code for a class, event
/// id for an event, the date for a day note, `vault:{uuid}` for a vault file).
///
/// A document, like `ScheduleStore` — JSON in LocalAppData, file owner-only —
/// held as a class that can be injected (for testing) or instantiated once.
/// </summary>
public class NotesStore
{
    private const string DefaultFileName = "notes.json";

    /// <summary>
    /// On-disk shape. A bare `Dictionary[string, Note]` (the legacy format) still loads —
    /// see `LoadDocument(...)`.
    /// </summary>
    private record Document
    {
        public required Dictionary<string, Note> Notes { get; set; }
        public required List<VaultNode> Vault { get; set; }
    }

    public Dictionary<string, Note> Notes { get; private set; }
    public List<VaultNode> Vault { get; private set; }
    private readonly string _filename;
    private readonly string? _directory;

    /// <summary>
    /// Create a NotesStore instance. By default, uses LocalAppData\PUPSISPortal\.
    /// For testing, pass a custom directory to use a temp location instead.
    /// </summary>
    public NotesStore(string filename = DefaultFileName, string? directory = null)
    {
        _filename = filename;
        _directory = directory;
        var document = LoadDocument();
        Notes = document.Notes;
        Vault = document.Vault;
    }

    public Note? Note(string key) => Notes.TryGetValue(key, out var note) ? note : null;

    public string Text(string key) => Notes.TryGetValue(key, out var note) ? note.Text : "";

    /// <summary>
    /// True only when there's actual content — an all-whitespace note reads as
    /// none, so the dot on a Today row means "there's something written here".
    /// </summary>
    public bool HasNote(string key)
    {
        if (!Notes.TryGetValue(key, out var note))
            return false;
        return !string.IsNullOrWhiteSpace(note.Text);
    }

    /// <summary>
    /// Sets a note's text, persisting immediately. Empty (or whitespace-only)
    /// text deletes the note rather than keeping a blank one around. A non-null
    /// `title` is recorded so history can label the note later; passing null keeps
    /// whatever title was already stored.
    /// </summary>
    public void SetText(string text, string key, string? title = null)
    {
        var trimmed = text.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            if (Notes.ContainsKey(key))
                Notes.Remove(key);
        }
        else
        {
            var preservedTitle = Notes.TryGetValue(key, out var existing) ? existing.Title : null;
            Notes[key] = new Note
            {
                Text = text,
                Updated = DateTime.UtcNow,
                Title = title ?? preservedTitle
            };
        }
        Persist();
    }

    // MARK: Vault CRUD

    /// <summary>
    /// Create a folder under `parentId` (root when null). Returns its id.
    /// </summary>
    public Guid AddFolder(string name, Guid? parentId)
    {
        var node = new VaultNode(
            Guid.NewGuid(),
            Cleaned(name, "New folder"),
            isFolder: true,
            children: new List<VaultNode>()
        );
        Insert(node, parentId, Vault);
        Persist();
        return node.Id;
    }

    /// <summary>
    /// Create a file under `parentId` (root when null). Returns its note key, so the
    /// caller can open it in the editor. The note itself is created on first save.
    /// </summary>
    public string AddFile(string name, Guid? parentId)
    {
        var key = $"vault:{Guid.NewGuid()}";
        var node = new VaultNode(
            Guid.NewGuid(),
            Cleaned(name, "Untitled"),
            isFolder: false,
            noteKey: key
        );
        Insert(node, parentId, Vault);
        Persist();
        return key;
    }

    public void RenameItem(Guid id, string name)
    {
        var trimmed = name.Trim();
        if (string.IsNullOrEmpty(trimmed))
            return;

        _ = Mutate(id, Vault, n => n.Name = trimmed);

        // Keep the file's stored note title in step, so history matches the tree.
        var node = FindNode(id, Vault);
        if (node?.NoteKey != null && Notes.TryGetValue(node.NoteKey, out var note))
        {
            Notes[node.NoteKey] = note with { Title = trimmed };
        }
        Persist();
    }

    /// <summary>
    /// Move a node into `newParentId` (root when null). No-ops if the target is the
    /// node itself or one of its descendants (which would detach the subtree).
    /// </summary>
    public void Move(Guid id, Guid? newParentId)
    {
        if (id == newParentId)
            return;
        if (newParentId.HasValue && IsDescendant(newParentId.Value, id))
            return;

        VaultNode? picked = null;
        Detach(id, Vault, ref picked);
        if (picked != null)
        {
            Insert(picked, newParentId, Vault);
            Persist();
        }
    }

    /// <summary>
    /// Remove a node (and, for a folder, its whole subtree) plus any notes it held.
    /// </summary>
    public void DeleteItem(Guid id)
    {
        var removedKeys = new List<string>();
        Remove(id, Vault, removedKeys);
        foreach (var key in removedKeys)
            Notes.Remove(key);
        Persist();
    }

    /// <summary>
    /// The display name of the vault file holding `key`, if any.
    /// </summary>
    public string? VaultName(string key)
    {
        return FindNodeByKey(key, Vault)?.Name;
    }

    /// <summary>
    /// The note key a vault node (by id) points at — for opening a dragged file.
    /// </summary>
    public string? NoteKeyForNodeId(Guid id)
    {
        return FindNode(id, Vault)?.NoteKey;
    }

    // MARK: Tree helpers (recursive over the reference-type tree)

    private static string Cleaned(string name, string fallback)
    {
        var trimmed = name.Trim();
        return string.IsNullOrEmpty(trimmed) ? fallback : trimmed;
    }

    private static void Insert(VaultNode node, Guid? parentId, List<VaultNode> nodes)
    {
        if (!parentId.HasValue)
        {
            nodes.Add(node);
            return;
        }

        for (var i = 0; i < nodes.Count; i++)
        {
            if (nodes[i].Id == parentId)
            {
                if (nodes[i].Children == null)
                    nodes[i].Children = new List<VaultNode>();
                nodes[i].Children.Add(node);
                return;
            }

            if (nodes[i].Children != null)
                Insert(node, parentId, nodes[i].Children);
        }
    }

    private static bool Mutate(Guid id, List<VaultNode> nodes, Action<VaultNode> change)
    {
        for (var i = 0; i < nodes.Count; i++)
        {
            if (nodes[i].Id == id)
            {
                change(nodes[i]);
                return true;
            }

            if (nodes[i].Children != null && Mutate(id, nodes[i].Children, change))
                return true;
        }
        return false;
    }

    private static void Remove(Guid id, List<VaultNode> nodes, List<string> removedKeys)
    {
        for (var i = 0; i < nodes.Count; i++)
        {
            if (nodes[i].Id == id)
            {
                CollectKeys(nodes[i], removedKeys);
                nodes.RemoveAt(i);
                return;
            }

            if (nodes[i].Children != null)
                Remove(id, nodes[i].Children, removedKeys);
        }
    }

    /// <summary>
    /// Detach a node from the tree, handing it back via `picked` (keeps its
    /// subtree intact for re-insertion elsewhere).
    /// </summary>
    private static void Detach(Guid id, List<VaultNode> nodes, ref VaultNode? picked)
    {
        for (var i = 0; i < nodes.Count; i++)
        {
            if (nodes[i].Id == id)
            {
                picked = nodes[i];
                nodes.RemoveAt(i);
                return;
            }

            if (nodes[i].Children != null)
            {
                Detach(id, nodes[i].Children, ref picked);
                if (picked != null)
                    return;
            }
        }
    }

    /// <summary>
    /// Is `candidate` inside `ancestor`'s subtree?
    /// </summary>
    private bool IsDescendant(Guid candidate, Guid ancestor)
    {
        var root = FindNode(ancestor, Vault);
        if (root == null)
            return false;
        return FindNode(candidate, root.Children ?? new List<VaultNode>()) != null;
    }

    private static void CollectKeys(VaultNode node, List<string> keys)
    {
        if (node.NoteKey != null)
            keys.Add(node.NoteKey);
        if (node.Children != null)
        {
            foreach (var child in node.Children)
                CollectKeys(child, keys);
        }
    }

    private static VaultNode? FindNode(Guid id, List<VaultNode> nodes)
    {
        foreach (var node in nodes)
        {
            if (node.Id == id)
                return node;
            if (node.Children != null)
            {
                var found = FindNode(id, node.Children);
                if (found != null)
                    return found;
            }
        }
        return null;
    }

    private static VaultNode? FindNodeByKey(string key, List<VaultNode> nodes)
    {
        foreach (var node in nodes)
        {
            if (node.NoteKey == key)
                return node;
            if (node.Children != null)
            {
                var found = FindNodeByKey(key, node.Children);
                if (found != null)
                    return found;
            }
        }
        return null;
    }

    // MARK: Disk

    private void Persist()
    {
        var document = new Document { Notes = Notes, Vault = Vault };
        JsonStore.Save(document, _filename, _directory);
    }

    private Document LoadDocument()
    {
        // Try to load as new format first
        var document = JsonStore.Load<Document>(_filename, _directory);
        if (document != null)
            return document;

        // Legacy format: a bare notes dict, no vault yet
        var legacyNotes = JsonStore.Load<Dictionary<string, Note>>(_filename, _directory);
        if (legacyNotes != null)
            return new Document { Notes = legacyNotes, Vault = new List<VaultNode>() };

        // Empty when nothing exists
        return new Document { Notes = new Dictionary<string, Note>(), Vault = new List<VaultNode>() };
    }
}
