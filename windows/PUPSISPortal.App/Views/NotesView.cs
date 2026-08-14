using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Shapes;
using Microsoft.Web.WebView2.Core;
using PUPSISPortal.App.Platform;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Views;

/// <summary>
/// The notes editor pane — the WinUI counterpart of macOS's WebNoteEditor.swift.
/// A slim native toolbar drives the CodeMirror 6 + KaTeX bundle (hosted in
/// WebView2, never edited on this side) through the same `PUPNotes.cmd(name,
/// arg)` bridge the bundle already exposes. Text changes flow back to
/// <see cref="NotesStore"/> over WebView2's message channel.
///
/// One editor pane, one note at a time — the mac app's closeable-tabs bar over
/// multiple open notes isn't ported here.
/// ponytail: single active note, no tab strip. Add tabs if switching notes
/// mid-task turns out to matter on Windows too.
/// </summary>
public sealed class NotesView : UserControl
{
    private static readonly string NotesAssetsDir =
        Path.Combine(AppContext.BaseDirectory, "Assets", "notes-editor");

    private readonly WebView2 _web = new();
    private readonly StackPanel _toolbar = new() { Orientation = Orientation.Horizontal, Spacing = 2 };

    private NotesStore? _notes;
    private string _currentKey = "";
    private string? _pendingTitle;
    private bool _coreReady;
    private bool _loaded;

    /// Fired when a `[[wikilink]]` is clicked in the editor, with the linked title.
    public event Action<string>? OpenLinkRequested;

    public Window? OwnerWindow { get; set; }

    public NotesView()
    {
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var toolbarScroll = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _toolbar,
        };
        BuildToolbar();
        Grid.SetRow(toolbarScroll, 0);

        Grid.SetRow(_web, 1);
        _ = InitWebViewAsync();

        root.Children.Add(toolbarScroll);
        root.Children.Add(_web);
        Content = root;
    }

    /// Switches the pane to a different note. The shell page is navigated to
    /// exactly once (see <see cref="InitWebViewAsync"/>); every note switch —
    /// this first one included — is a content push, not a fresh navigation.
    public void Open(NotesStore notes, string key, string? title = null)
    {
        _notes = notes;
        _currentKey = key;
        _pendingTitle = title;
        if (_loaded)
            PushContent();
        // else: the pending NavigationCompleted handler picks it up once the
        // shell finishes loading (it checks _notes != null).
    }

    // MARK: WebView2 plumbing

    private async Task InitWebViewAsync()
    {
        await _web.EnsureCoreWebView2Async();
        var core = _web.CoreWebView2;
        core.SetVirtualHostNameToFolderMapping(
            "pupimg.local", NoteImageStore.Directory, CoreWebView2HostResourceAccessKind.Allow);
        // The shell + bundle are served as static files, not built into a string —
        // NavigateToString caps around 2MB and bundle.js alone is 1.9MB.
        core.SetVirtualHostNameToFolderMapping(
            "notes.local", NotesAssetsDir, CoreWebView2HostResourceAccessKind.Allow);
        core.NavigationCompleted += (_, _) => { _loaded = true; if (_notes != null) PushContent(); };
        core.WebMessageReceived += OnWebMessage;
        _coreReady = true;
        core.Navigate("https://notes.local/shell.html");
    }

    private void PushContent()
    {
        var json = JsonQuoted(_notes!.Text(_currentKey));
        var key = JsonQuoted(_currentKey);
        _ = _web.CoreWebView2.ExecuteScriptAsync($"PUPNotes.setContent({json}, {key});");
    }

    private void OnWebMessage(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        using var doc = JsonDocument.Parse(e.WebMessageAsJson);
        var root = doc.RootElement;
        var channel = root.TryGetProperty("channel", out var c) ? c.GetString() : null;

        switch (channel)
        {
            case "notes":
                var text = root.GetProperty("text").GetString() ?? "";
                var key = root.GetProperty("key").GetString() ?? "";
                // Only the pane's current note owns the pending title; a late
                // edit from a note we've since navigated away from keeps its own.
                var title = key == _currentKey ? _pendingTitle : _notes?.Note(key)?.Title;
                _notes?.SetText(text, key, title);
                break;

            case "open":
                var linkTitle = root.GetProperty("title").GetString();
                if (linkTitle != null) OpenLinkRequested?.Invoke(linkTitle);
                break;

            case "image":
                var base64 = root.GetProperty("base64").GetString();
                var ext = root.GetProperty("ext").GetString() ?? "png";
                if (base64 != null && NoteImageStore.Save(base64, ext) is { } name)
                {
                    var url = JsonQuoted($"https://pupimg.local/{name}");
                    _ = _web.CoreWebView2.ExecuteScriptAsync($"PUPNotes.insertImage({url});");
                }
                break;
        }
    }

    // MARK: Toolbar

    private void BuildToolbar()
    {
        HeadingMenu();
        Divider();
        Btn("", "Bold", () => Cmd("bold"));          // Bold glyph
        Btn("", "Italic", () => Cmd("italic"));
        Btn("", "Strikethrough", () => Cmd("strike"));
        Btn("", "Highlight", () => Cmd("highlight"));
        ColorMenu();
        CodeMenu();
        Btn("", "Math", () => Cmd("math"));
        Btn("", "LaTeX document", () => Cmd("latexdoc"));
        Divider();
        Btn("", "Bullet list", () => Cmd("bullet"));
        Btn("", "Numbered list", () => Cmd("numbered"));
        Btn("", "Checklist", () => Cmd("checklist"));
        Btn("", "Quote", () => Cmd("quote"));
        Btn("", "Divider", () => Cmd("rule"));
        Btn("", "Table", () => Cmd("table"));
        Divider();
        Btn("", "Insert image…", InsertImageAsync);
        Btn("", "Link", () => Cmd("link"));
        Btn("", "Link to another note", () => Cmd("wikilink"));
        Btn("", "Insert today's date", () => Cmd("datestamp", DateTime.Now.ToString("MMMM d, yyyy")));
    }

    private void Btn(string glyph, string tip, Action click)
    {
        var b = new Button
        {
            Content = new FontIcon { Glyph = glyph, FontSize = 14 },
            Padding = new Thickness(6),
        };
        b.Click += (_, _) => click();
        ToolTipService.SetToolTip(b, tip);
        _toolbar.Children.Add(b);
    }

    private void HeadingMenu()
    {
        var flyout = new MenuFlyout();
        foreach (var (label, level) in new[] { ("Heading 1", "1"), ("Heading 2", "2"), ("Heading 3", "3") })
        {
            var item = new MenuFlyoutItem { Text = label };
            item.Click += (_, _) => Cmd("heading", level);
            flyout.Items.Add(item);
        }
        flyout.Items.Add(new MenuFlyoutSeparator());
        var normal = new MenuFlyoutItem { Text = "Normal text" };
        normal.Click += (_, _) => Cmd("heading", "0");
        flyout.Items.Add(normal);

        var b = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Flyout = flyout };
        ToolTipService.SetToolTip(b, "Heading level");
        _toolbar.Children.Add(b);
    }

    private void ColorMenu()
    {
        var colors = new (string Name, string Hex)[]
        {
            ("Red", "e5484d"), ("Orange", "e57a00"), ("Yellow", "d4a300"), ("Green", "2f9e44"),
            ("Teal", "0d9488"), ("Blue", "3b7dd8"), ("Purple", "8f5cd8"), ("Pink", "d6409f"),
        };
        var flyout = new MenuFlyout();
        foreach (var (name, hex) in colors)
        {
            var item = new MenuFlyoutItem { Text = name };
            item.Click += (_, _) => Cmd("color", hex);
            flyout.Items.Add(item);
        }
        var b = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Flyout = flyout };
        ToolTipService.SetToolTip(b, "Text color");
        _toolbar.Children.Add(b);
    }

    // Canonical language ids match the bundle's codeLanguages map.
    private static readonly (string Label, string Id)[] Languages =
    {
        ("Plain", ""), ("Python", "python"), ("JavaScript", "javascript"), ("TypeScript", "typescript"),
        ("C++", "cpp"), ("C", "c"), ("Java", "java"), ("Rust", "rust"), ("Go", "go"),
        ("HTML", "html"), ("CSS", "css"), ("JSON", "json"), ("SQL", "sql"), ("PHP", "php"), ("XML", "xml"),
    };

    private void CodeMenu()
    {
        var flyout = new MenuFlyout();
        foreach (var (label, id) in Languages)
        {
            var item = new MenuFlyoutItem { Text = label };
            item.Click += (_, _) => Cmd("codeblock", id);
            flyout.Items.Add(item);
        }
        var b = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Flyout = flyout };
        ToolTipService.SetToolTip(b, "Code block");
        _toolbar.Children.Add(b);
    }

    private void Divider() => _toolbar.Children.Add(new Rectangle
    {
        Width = 1, Height = 14, Fill = new Microsoft.UI.Xaml.Media.SolidColorBrush(
            Microsoft.UI.Colors.Gray) { Opacity = 0.3 },
        Margin = new Thickness(4, 0, 4, 0),
    });

    private async void InsertImageAsync()
    {
        if (OwnerWindow is null) return;
        var picker = new Windows.Storage.Pickers.FileOpenPicker();
        picker.FileTypeFilter.Add(".png");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");
        picker.FileTypeFilter.Add(".gif");
        picker.FileTypeFilter.Add(".webp");
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(OwnerWindow);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var file = await picker.PickSingleFileAsync();
        if (file is null) return;

        var bytes = await Windows.Storage.FileIO.ReadBufferAsync(file);
        var base64 = Convert.ToBase64String(bytes.ToArray());
        var ext = Path.GetExtension(file.Path).TrimStart('.');
        if (NoteImageStore.Save(base64, ext) is { } name)
        {
            var url = JsonQuoted($"https://pupimg.local/{name}");
            _ = _web.CoreWebView2.ExecuteScriptAsync($"window.PUPNotes && PUPNotes.insertImage({url});");
        }
    }

    private void Cmd(string name, string? arg = null)
    {
        if (!_coreReady) return;
        var argJs = arg is null ? "undefined" : JsonQuoted(arg);
        _ = _web.CoreWebView2.ExecuteScriptAsync($"window.PUPNotes && PUPNotes.cmd('{name}', {argJs});");
    }

    // MARK: Helpers

    /// JSON-encodes a string for safe interpolation into a script string handed
    /// to ExecuteScriptAsync -- U+2028/U+2029 are invalid unescaped inside a JS
    /// string literal, and the `<` escape is cheap insurance against the text
    /// ever landing inside an HTML <script> tag. Mirrors the macOS host's
    /// `jsonString(_:)`.
    private static string JsonQuoted(string s) =>
        JsonSerializer.Serialize(s)
            .Replace("<", "\\u003c")
            .Replace("\u2028", "\\u2028")
            .Replace("\u2029", "\\u2029");
}
