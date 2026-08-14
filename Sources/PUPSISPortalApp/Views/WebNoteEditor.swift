import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

/// The notes editor, web-based (CodeMirror 6 + KaTeX, bundled offline). This is
/// how Obsidian works: `$$…$$` / `$…$` render inline live as you type — no click —
/// and moving the caret into a math span reveals its source to edit. A slim native
/// toolbar drives formatting through the bundle. The sidebar (vault, schedule) stays
/// native; only this pane is a `WKWebView`.
///
/// Text flows back to `NotesStore` over a script-message bridge; note switches push
/// content in via `setContent`. The note's stored text is always plain Markdown.
struct WebNoteEditor: View {
    @ObservedObject var notes: NotesStore
    let noteKey: String
    var title: String? = nil
    var onOpenNote: ((String) -> Void)? = nil
    /// "Next class" / "today" date labels for the Add-date menu — non-nil only
    /// when this note is a shared per-subject class note.
    var addDateOptions: (next: String, today: String)? = nil
    /// Read for the AI-drafting toggle and model name; the button is absent
    /// entirely when the feature is off.
    @ObservedObject var preferences: Preferences

    @Environment(\.palette) private var palette
    @StateObject private var bridge = WebNoteBridge()
    @State private var showLanguages = false
    @State private var showColors = false
    @State private var customColor: Color = .red

    private static let colors: [(name: String, hex: String)] = [
        ("Red", "e5484d"), ("Orange", "e57a00"), ("Yellow", "d4a300"), ("Green", "2f9e44"),
        ("Teal", "0d9488"), ("Blue", "3b7dd8"), ("Purple", "8f5cd8"), ("Pink", "d6409f"),
    ]

    // Fenced-code languages (canonical ids match editor.js codeLanguages).
    private static let languages: [(label: String, id: String)] = [
        ("Plain", ""), ("Python", "python"), ("JavaScript", "javascript"), ("TypeScript", "typescript"),
        ("C++", "cpp"), ("C", "c"), ("Java", "java"), ("Rust", "rust"), ("Go", "go"),
        ("HTML", "html"), ("CSS", "css"), ("JSON", "json"), ("SQL", "sql"), ("PHP", "php"), ("XML", "xml"),
    ]

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            WebNoteView(notes: notes, noteKey: noteKey, title: title, bridge: bridge, onOpenNote: onOpenNote)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(palette.accent)
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                headingMenu
                divider
                button("bold", "Bold") { bridge.cmd("bold") }
                button("italic", "Italic") { bridge.cmd("italic") }
                button("strikethrough", "Strikethrough") { bridge.cmd("strike") }
                button("highlighter", "Highlight") { bridge.cmd("highlight") }
                colorButton
                codeButton
                button("x.squareroot", "Math") { bridge.cmd("math") }
                button("function", "LaTeX document") { bridge.cmd("latexdoc") }
                divider
                button("list.bullet", "Bullet list") { bridge.cmd("bullet") }
                button("list.number", "Numbered list") { bridge.cmd("numbered") }
                button("checklist", "Checklist") { bridge.cmd("checklist") }
                button("text.quote", "Quote") { bridge.cmd("quote") }
                button("minus", "Divider") { bridge.cmd("rule") }
                button("tablecells", "Table") { bridge.cmd("table") }
                divider
                button("photo", "Insert image…") { pickImage() }
                button("link", "Link") { bridge.cmd("link") }
                button("link.badge.plus", "Link to another note") { bridge.cmd("wikilink") }
                if let options = addDateOptions {
                    divider
                    dateMenu(options)
                }
                // No model chosen yet means nothing to ask — Settings picks one
                // from what's actually installed.
                if preferences.aiEnabled && !preferences.aiModel.isEmpty {
                    divider
                    draftButton
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ask the local model to continue the selection (or the whole note, when
    /// nothing is selected). Hidden entirely unless the beta toggle is on.
    @ViewBuilder
    private var draftButton: some View {
        if bridge.isDrafting {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
                .help("Drafting…")
        } else {
            button("sparkles", bridge.draftError ?? "Draft with \(preferences.aiModel)") {
                draft()
            }
            .foregroundStyle(bridge.draftError == nil ? palette.accent : .orange)
        }
    }

    private func draft() {
        Task {
            bridge.draftError = nil
            let selection = await bridge.selection()
            guard !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                bridge.draftError = "Write something first — there's nothing to work from."
                return
            }
            bridge.isDrafting = true
            defer { bridge.isDrafting = false }
            do {
                let text = try await OllamaClient().generate(
                    model: preferences.aiModel, selection: selection
                )
                bridge.insertText(text)
            } catch {
                // Stays on the button as a tooltip rather than an alert: a model
                // that isn't running is a setup problem, not an emergency.
                bridge.draftError = error.localizedDescription
            }
        }
    }

    // Code button → horizontal language picker; click a language to insert its ```block.
    // Appends a "## <date>" heading to the note as a new dated log entry.
    // Offers the subject's next scheduled meeting (default) and today, so a
    // note written ahead of the class still lands under the date it's for.
    private func dateMenu(_ options: (next: String, today: String)) -> some View {
        Menu {
            Button("Next class · \(options.next)") { bridge.cmd("datestamp", options.next) }
            if options.today != options.next {
                Button("Today · \(options.today)") { bridge.cmd("datestamp", options.today) }
            }
        } label: {
            Image(systemName: "calendar.badge.plus").frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.borderless)
        .menuIndicator(.hidden).fixedSize().help("Add dated entry")
    }

    private var headingMenu: some View {
        Menu {
            Button("Heading 1") { bridge.cmd("heading", "1") }
            Button("Heading 2") { bridge.cmd("heading", "2") }
            Button("Heading 3") { bridge.cmd("heading", "3") }
            Divider()
            Button("Normal text") { bridge.cmd("heading", "0") }
        } label: {
            Image(systemName: "number").frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.borderless)
        .menuIndicator(.hidden).fixedSize().help("Heading level")
    }

    // A visual color picker: a grid of preset swatches plus a native color well
    // for any custom color. Applies to the selected text via cmd("color", hex).
    private var colorButton: some View {
        Button { showColors = true } label: {
            Image(systemName: "paintpalette").frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help("Text color")
        .popover(isPresented: $showColors, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Text color").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.colors, id: \.hex) { c in
                        Button {
                            bridge.cmd("color", c.hex)
                            showColors = false
                        } label: {
                            Circle()
                                .fill(Color(hex: c.hex) ?? .gray)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain).help(c.name)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    ColorPicker("Custom", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                    Button("Apply custom") {
                        if let hex = customColor.hex {
                            bridge.cmd("color", String(hex.dropFirst())) // strip '#'
                        }
                        showColors = false
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .frame(width: 188)
        }
    }

    // Native file picker → copy the image into app storage → insert it inline
    // at the caret (same pupimg:// pipeline as paste/drop).
    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        panel.message = "Choose an image to insert"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let inserted = NoteImages.save(base64: data.base64EncodedString(), ext: url.pathExtension)
        else { return }
        bridge.insertImage(inserted)
    }

    private var codeButton: some View {
        Button { showLanguages = true } label: {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help("Code block")
        .popover(isPresented: $showLanguages, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Code block").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Self.languages, id: \.id) { lang in
                        Button {
                            bridge.cmd("codeblock", lang.id)
                            showLanguages = false
                        } label: {
                            Text(lang.label)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .frame(width: 300)
        }
    }

    private var divider: some View { Divider().frame(height: 14).padding(.horizontal, 2) }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help(help)
    }
}

/// A string as a **quoted** JS literal, safe to drop straight into a script.
/// Both the initial-content shell and the toolbar's insert paths go through
/// this — note text and model output are equally arbitrary.
func jsNoteString(_ s: String) -> String {
    let json = (try? JSONSerialization.data(withJSONObject: [s]))
        .flatMap { String(data: $0, encoding: .utf8) }
        .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    // Escape `<` so note text can't break out of an inline <script> (e.g.
    // "</script>"), plus the JS-invalid line/paragraph separators.
    return json
        .replacingOccurrences(of: "<", with: "\\u003c")
        .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
}

/// Holds the live `WKWebView` so the SwiftUI toolbar can run editor commands.
@MainActor
final class WebNoteBridge: ObservableObject {
    weak var webView: WKWebView?

    /// A draft is in flight; the toolbar shows a spinner and blocks a second ask.
    @Published var isDrafting = false
    /// Why the last draft produced nothing. Cleared when the next one starts.
    @Published var draftError: String?

    func cmd(_ name: String, _ arg: String? = nil) {
        let argJS = arg.map { "'\($0)'" } ?? "undefined"
        webView?.evaluateJavaScript("window.PUPNotes && PUPNotes.cmd('\(name)', \(argJS));", completionHandler: nil)
    }

    /// Insert an image at the editor's caret. `url` is an app-generated
    /// `pupimg://<uuid>.<ext>` — no user text, safe to inline.
    func insertImage(_ url: String) {
        webView?.evaluateJavaScript("window.PUPNotes && PUPNotes.insertImage('\(url)');", completionHandler: nil)
    }

    /// The selected text, or the whole note when nothing is selected.
    func selection() async -> String {
        guard let webView else { return "" }
        let value = try? await webView.evaluateJavaScript("window.PUPNotes ? PUPNotes.getSelection() : '';")
        return value as? String ?? ""
    }

    /// Insert model output after the selection. Passed as a JSON literal rather
    /// than interpolated: generated text is arbitrary and would otherwise break
    /// out of the quotes at the first apostrophe.
    func insertText(_ text: String) {
        webView?.evaluateJavaScript("window.PUPNotes && PUPNotes.insertText(\(jsNoteString(text)));",
                                    completionHandler: nil)
    }
}

/// Serves saved note images back into the webview under `pupimg://<name>`.
/// The files themselves are `Core/NoteImages`, which `NotesStore` also needs.
private final class PupImageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let host = url.host,
              let data = try? Data(contentsOf: NoteImages.url(for: host)) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let ext = NoteImages.url(for: host).pathExtension
        let response = URLResponse(
            url: url, mimeType: "image/\(ext.isEmpty ? "png" : ext)",
            expectedContentLength: data.count, textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private struct WebNoteView: NSViewRepresentable {
    @ObservedObject var notes: NotesStore
    let noteKey: String
    var title: String?
    let bridge: WebNoteBridge
    var onOpenNote: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "notes")
        config.userContentController.add(context.coordinator, name: "open")
        config.userContentController.add(context.coordinator, name: "image")
        // loadHTMLString(baseURL: nil) can't reach file://, so pasted/dropped
        // images round-trip through this custom scheme instead.
        config.setURLSchemeHandler(PupImageSchemeHandler(), forURLScheme: "pupimg")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        bridge.webView = webView
        context.coordinator.currentKey = noteKey
        context.coordinator.loaded = false
        webView.loadHTMLString(Self.html(initial: notes.text(for: noteKey), key: noteKey), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Push content only when the selected note actually changes (not on our own
        // edits echoing back), and only once the editor bundle has loaded.
        if context.coordinator.currentKey != noteKey {
            context.coordinator.currentKey = noteKey
            if context.coordinator.loaded {
                let json = Self.jsonString(notes.text(for: noteKey))
                let keyJSON = Self.jsonString(noteKey)
                webView.evaluateJavaScript("PUPNotes.setContent(\(json), \(keyJSON));", completionHandler: nil)
            }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "notes")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "open")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "image")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WebNoteView
        var currentKey: String = ""
        var loaded = false
        init(_ parent: WebNoteView) { self.parent = parent }

        // JS → Swift: either the doc changed ("notes") or a [[wikilink]] was
        // clicked ("open"). The edit payload carries the key it belongs to, so
        // an edit that arrives after a note switch still saves to its own note.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch message.name {
            case "notes":
                guard let text = body["text"] as? String, let key = body["key"] as? String else { return }
                // Only the open note's title is current; a late edit keeps its own.
                let title = key == currentKey ? parent.title : parent.notes.note(for: key)?.title
                parent.notes.setText(text, for: key, title: title)
            case "open":
                guard let title = body["title"] as? String else { return }
                parent.onOpenNote?(title)
            case "image":
                // A pasted/dropped image arrives as base64; save it, then hand the
                // resulting pupimg:// URL back so the editor inserts it at the caret.
                guard let base64 = body["base64"] as? String, let ext = body["ext"] as? String,
                      let inserted = NoteImages.save(base64: base64, ext: ext) else { return }
                let js = "PUPNotes.insertImage(\(WebNoteView.jsonString(inserted)));"
                message.webView?.evaluateJavaScript(js, completionHandler: nil)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
        }
    }

    // MARK: HTML shell

    private static let bundle: String? = {
        guard let url = Bundle.main.url(forResource: "notes-editor.bundle", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    private static func jsonString(_ s: String) -> String { jsNoteString(s) }

    private static func html(initial: String, key: String) -> String {
        guard let bundle else {
            return "<html><body style=\"font-family:-apple-system;padding:16px;color:#900\">Notes editor bundle missing.</body></html>"
        }
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; --fg:#1a1a1a; }
          @media (prefers-color-scheme: dark) { :root { --fg:#e8e8e8; } }
          html,body { margin:0; height:100%; background:transparent; }
          #editor { height:100%; }
          .cm-editor { height:100%; background:transparent; color:var(--fg);
            font:15px/1.55 -apple-system, system-ui, sans-serif; }
          .cm-editor.cm-focused { outline:none; }
          .cm-scroller { padding:6px 10px; overflow:auto; }
          .cm-content { max-width:none; }
          .cm-cursor { border-left-color:var(--fg); }
          .pup-math { font-size:1.05em; }
          .pup-math-block { display:block; margin:6px 0; }
          /* Discord-style fenced code block: dark rounded box, mono, highlighted. */
          .cm-line.pup-code {
            background:#1e1f22; color:#dbdee1;
            font-family:ui-monospace, "SF Mono", Menlo, monospace; font-size:0.9em;
            padding-left:14px; padding-right:14px;
          }
          .cm-line.pup-code-first {
            border-top-left-radius:6px; border-top-right-radius:6px;
            padding-top:8px; margin-top:4px;
          }
          .cm-line.pup-code-last {
            border-bottom-left-radius:6px; border-bottom-right-radius:6px;
            padding-bottom:8px; margin-bottom:4px;
          }
          /* Language badge + copy button header (replaces the ```lang line). */
          .pup-code-header { display:flex; align-items:center; justify-content:space-between; gap:8px; }
          .pup-lang {
            font-family:-apple-system, system-ui, sans-serif; font-size:11px; font-weight:700;
            text-transform:uppercase; letter-spacing:0.04em; color:var(--lang, #8a8f98);
          }
          .pup-copy {
            font:11px -apple-system, system-ui, sans-serif; color:#b5bac1;
            background:#313338; border:1px solid #3f4147; border-radius:4px;
            padding:1px 8px; cursor:pointer;
          }
          .pup-copy:hover { background:#3a3c41; color:#fff; }
          .pup-hidden-fence { display:none; }
          .pup-hr { display:block; width:100%; height:0; border-top:2px solid color-mix(in srgb, var(--fg) 40%, transparent); margin:12px 0; }
          .pup-checkbox { width:14px; height:14px; margin:0 2px 0 0; vertical-align:-2px; cursor:pointer; }
          .pup-wikilink {
            color:#3b7dd8; background:color-mix(in srgb, #3b7dd8 12%, transparent);
            border-radius:4px; padding:0 4px; cursor:pointer;
          }
          .pup-wikilink:hover { background:color-mix(in srgb, #3b7dd8 22%, transparent); }
          .pup-image { max-width:100%; border-radius:8px; display:block; margin:6px 0; }
          /* pupdb: the interactive table / checklist-database widget. */
          .pup-db { margin:10px 0; overflow-x:auto; }
          .pup-db table { border-collapse:collapse; table-layout:fixed; width:auto; font:13px -apple-system, system-ui, sans-serif; }
          .pup-db th, .pup-db td { border:1px solid color-mix(in srgb, var(--fg) 14%, transparent); padding:4px 6px; text-align:left; overflow:hidden; position:relative; }
          .pup-db th { background:color-mix(in srgb, var(--fg) 6%, transparent); }
          .pup-db-cell { padding-right:14px; }
          .pup-db-cellcolor {
            position:absolute; right:3px; top:50%; transform:translateY(-50%);
            border:none; background:transparent; cursor:pointer; font-size:9px; padding:0; line-height:1;
            color:color-mix(in srgb, var(--fg) 45%, transparent); opacity:0; transition:opacity 0.12s;
          }
          .pup-db td:hover .pup-db-cellcolor { opacity:0.7; }
          .pup-db-cellcolor:hover { opacity:1; }
          .pup-db-actioncol { width:34px; }
          .pup-db-name { border:none; background:transparent; color:var(--fg); font:inherit; font-weight:600; width:calc(100% - 30px); }
          .pup-db-name:focus { outline:none; }
          /* Drag handle on a column's right edge. */
          .pup-db-resize { position:absolute; top:0; right:-3px; width:6px; height:100%; cursor:col-resize; z-index:2; }
          .pup-db-resize:hover { background:color-mix(in srgb, #3b7dd8 50%, transparent); }
          .pup-db-add, .pup-db-addrow {
            border:none; background:transparent; color:color-mix(in srgb, var(--fg) 55%, transparent);
            cursor:pointer; font:12px -apple-system, system-ui, sans-serif;
          }
          /* × / ▾ column and row controls: hidden until the cursor is over that
             header or row (kept out of the way, revealed when near). */
          .pup-db-colmenu, .pup-db-del {
            border:none; background:transparent; color:color-mix(in srgb, var(--fg) 55%, transparent);
            cursor:pointer; font:12px -apple-system, system-ui, sans-serif;
            opacity:0; transition:opacity 0.12s;
          }
          .pup-db th:hover .pup-db-colmenu, .pup-db tbody tr:hover .pup-db-del { opacity:1; }
          .pup-db-colmenu:hover, .pup-db-del:hover { color:#e5484d; }
          .pup-db-add { font-weight:700; }
          .pup-db-addrow {
            margin-top:6px; padding:2px 10px; border:1px dashed color-mix(in srgb, var(--fg) 25%, transparent);
            border-radius:5px;
          }
          .pup-db-cell { border:none; background:transparent; color:var(--fg); font:inherit; width:100%; }
          .pup-db-cell:focus { outline:none; }
          .pup-db-pill {
            border:none; border-radius:5px; padding:2px 8px; font:12px -apple-system, system-ui, sans-serif;
            font-weight:600; color:#fff; background:var(--pill, #8a8f98); cursor:pointer;
          }
          .pup-db-pill-empty { background:color-mix(in srgb, var(--fg) 15%, transparent); color:var(--fg); }
          .pup-db-menu {
            position:fixed; background:#26282c; border:1px solid #3f4147; border-radius:6px; padding:4px;
            z-index:1000; min-width:140px; box-shadow:0 4px 16px rgba(0,0,0,0.3);
          }
          .pup-db-menuitem {
            display:flex; align-items:center; gap:6px; padding:4px 8px; border-radius:4px;
            cursor:pointer; color:#dbdee1; font:12px -apple-system, system-ui, sans-serif;
          }
          .pup-db-menuitem:hover { background:#313338; }
          .pup-db-menuitem:not(.pup-db-menuitem-plain)::before {
            content:""; width:8px; height:8px; border-radius:50%; background:var(--pill, #8a8f98); flex:none;
          }
          .pup-db-opt-del { color:#8a8f98; padding:0 2px; }
          .pup-db-opt-del:hover { color:#e5484d; }
          .pup-db-addopt { border-top:1px solid #3f4147; margin-top:4px; padding-top:6px; }
          .pup-db-optinput {
            width:100%; box-sizing:border-box; background:#1e1f22; border:1px solid #3f4147;
            border-radius:4px; color:#dbdee1; font:12px -apple-system, system-ui, sans-serif; padding:4px 6px;
          }
          .pup-db-optinput:focus { outline:none; border-color:#5865f2; }
          .pup-db-swatches { display:flex; gap:4px; margin:6px 0; flex-wrap:wrap; }
          .pup-db-swatch { width:16px; height:16px; border-radius:50%; border:2px solid transparent; cursor:pointer; padding:0; }
          .pup-db-swatch.sel { border-color:#fff; }
          .pup-db-optadd {
            width:100%; background:#5865f2; border:none; border-radius:4px; color:#fff;
            font:12px -apple-system, system-ui, sans-serif; font-weight:600; padding:5px; cursor:pointer;
          }
          .pup-db-optadd:hover { background:#4752c4; }
        </style>
        <script>\(bundle)</script>
        </head><body>
        <div id="editor"></div>
        <script> PUPNotes.initEditor(\(jsonString(initial)), \(jsonString(key))); </script>
        </body></html>
        """
    }
}
