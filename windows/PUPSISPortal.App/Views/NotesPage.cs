using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Views;

/// <summary>
/// The Notes screen: a native vault tree (folders + files, the WinUI counterpart
/// of the "Vault" section in macOS's AgendaView.swift) beside a single
/// <see cref="NotesView"/> editor pane. The mac app also keys notes off classes/
/// days/events and opens several as closeable tabs; only the freeform vault —
/// the standalone notes app — is ported here.
/// ponytail: vault only, no class/day/event notes and no tab bar. Wire those in
/// once the calendar UI (Stage 4's port) grows a "notes" affordance that needs one.
/// </summary>
public sealed class NotesPage : UserControl
{
    private readonly NotesStore _notes = new();
    private readonly TreeView _tree = new() { SelectionMode = TreeViewSelectionMode.Single };
    private readonly NotesView _editor = new();

    public NotesPage()
    {
        var root = new Grid { ColumnSpacing = 0 };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var sidebar = new Grid();
        sidebar.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        sidebar.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, Margin = new Thickness(8) };
        var newFile = new Button { Content = new TextBlock { Text = "New note" } };
        var newFolder = new Button { Content = new TextBlock { Text = "New folder" } };
        var rename = new Button { Content = new TextBlock { Text = "Rename" } };
        var delete = new Button { Content = new TextBlock { Text = "Delete" } };
        newFile.Click += async (_, _) => await AddFileAsync(null);
        newFolder.Click += async (_, _) => await AddFolderAsync(null);
        rename.Click += async (_, _) => { if (SelectedNode() is { } n) await RenameAsync(n); };
        delete.Click += async (_, _) => { if (SelectedNode() is { } n) await DeleteAsync(n); };
        toolbar.Children.Add(newFile);
        toolbar.Children.Add(newFolder);
        toolbar.Children.Add(rename);
        toolbar.Children.Add(delete);
        Grid.SetRow(toolbar, 0);

        _tree.SelectionChanged += OnSelectionChanged;
        Grid.SetRow(_tree, 1);

        sidebar.Children.Add(toolbar);
        sidebar.Children.Add(_tree);
        Grid.SetColumn(sidebar, 0);

        Grid.SetColumn(_editor, 1);

        root.Children.Add(sidebar);
        root.Children.Add(_editor);
        Content = root;

        RebuildTree();
    }

    public Window? OwnerWindow
    {
        get => _editor.OwnerWindow;
        set => _editor.OwnerWindow = value;
    }

    // MARK: Tree

    private sealed class VaultNodeVM
    {
        public VaultNode Node { get; }
        public VaultNodeVM(VaultNode node) => Node = node;
        public override string ToString() => (Node.IsFolder ? "\U0001F4C1 " : "\U0001F4C4 ") + Node.Name;
    }

    private void RebuildTree()
    {
        _tree.RootNodes.Clear();
        foreach (var node in _notes.Vault)
            _tree.RootNodes.Add(BuildTreeNode(node));
    }

    private static TreeViewNode BuildTreeNode(VaultNode node)
    {
        var tvn = new TreeViewNode { Content = new VaultNodeVM(node), IsExpanded = false };
        if (node.Children != null)
            foreach (var child in node.Children)
                tvn.Children.Add(BuildTreeNode(child));
        return tvn;
    }

    private void OnSelectionChanged(TreeView sender, TreeViewSelectionChangedEventArgs e)
    {
        // Populated via RootNodes (not ItemsSource), so selection carries the
        // TreeViewNode itself — its Content is our view-model.
        if (e.AddedItems.Count == 0) return;
        if (e.AddedItems[0] is not TreeViewNode node) return;
        if (node.Content is not VaultNodeVM vm || vm.Node.IsFolder) return;
        _editor.Open(_notes, vm.Node.NoteKey!, vm.Node.Name);
    }

    private Guid? SelectedFolderId()
    {
        if (_tree.SelectedNode?.Content is not VaultNodeVM vm) return null;
        return vm.Node.IsFolder ? vm.Node.Id : null; // dropping a file's parent isn't tracked here; root fallback
    }

    private VaultNode? SelectedNode() =>
        _tree.SelectedNode?.Content is VaultNodeVM vm ? vm.Node : null;

    // MARK: CRUD (native ContentDialog prompts — no extra dependency)

    private async Task AddFileAsync(Guid? parentId)
    {
        var name = await PromptAsync("New note", "Note name", "Untitled");
        if (name is null) return;
        var key = _notes.AddFile(name, parentId ?? SelectedFolderId());
        RebuildTree();
        _editor.Open(_notes, key, name);
    }

    private async Task AddFolderAsync(Guid? parentId)
    {
        var name = await PromptAsync("New folder", "Folder name", "New folder");
        if (name is null) return;
        _notes.AddFolder(name, parentId ?? SelectedFolderId());
        RebuildTree();
    }

    private async Task RenameAsync(VaultNode node)
    {
        var name = await PromptAsync("Rename", "Name", node.Name);
        if (name is null) return;
        _notes.RenameItem(node.Id, name);
        RebuildTree();
    }

    private async Task DeleteAsync(VaultNode node)
    {
        var dialog = new ContentDialog
        {
            Title = "Delete " + (node.IsFolder ? "folder" : "note") + "?",
            Content = node.IsFolder
                ? $"\"{node.Name}\" and everything inside it will be removed."
                : $"\"{node.Name}\" will be removed.",
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _notes.DeleteItem(node.Id);
        RebuildTree();
    }

    private async Task<string?> PromptAsync(string title, string label, string initial)
    {
        var box = new TextBox { Header = label, Text = initial };
        var dialog = new ContentDialog
        {
            Title = title,
            Content = box,
            PrimaryButtonText = "OK",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary ? box.Text.Trim() : null;
    }
}
