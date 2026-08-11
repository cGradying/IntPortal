import SwiftUI
import WebKit

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

    @Environment(\.palette) private var palette
    @StateObject private var bridge = WebNoteBridge()
    @State private var showLanguages = false

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
            WebNoteView(notes: notes, noteKey: noteKey, title: title, bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(palette.accent)
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                button("number", "Heading") { bridge.cmd("heading") }
                divider
                button("bold", "Bold") { bridge.cmd("bold") }
                button("italic", "Italic") { bridge.cmd("italic") }
                button("strikethrough", "Strikethrough") { bridge.cmd("strike") }
                button("highlighter", "Highlight") { bridge.cmd("highlight") }
                colorMenu
                codeButton
                button("x.squareroot", "Math") { bridge.cmd("math") }
                divider
                button("list.bullet", "Bullet list") { bridge.cmd("bullet") }
                button("list.number", "Numbered list") { bridge.cmd("numbered") }
                button("checklist", "Checklist") { bridge.cmd("checklist") }
                button("text.quote", "Quote") { bridge.cmd("quote") }
                divider
                button("link", "Link") { bridge.cmd("link") }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Code button → horizontal language picker; click a language to insert its ```block.
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

    private var colorMenu: some View {
        Menu {
            ForEach(Self.colors, id: \.hex) { color in
                Button(color.name) { bridge.cmd("color", color.hex) }
            }
        } label: {
            Image(systemName: "paintpalette").frame(width: 20, height: 20)
        }
        .menuIndicator(.hidden).fixedSize().help("Text color")
    }

    private var divider: some View { Divider().frame(height: 14).padding(.horizontal, 2) }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help(help)
    }
}

/// Holds the live `WKWebView` so the SwiftUI toolbar can run editor commands.
final class WebNoteBridge: ObservableObject {
    weak var webView: WKWebView?

    func cmd(_ name: String, _ arg: String? = nil) {
        let argJS = arg.map { "'\($0)'" } ?? "undefined"
        webView?.evaluateJavaScript("window.PUPNotes && PUPNotes.cmd('\(name)', \(argJS));", completionHandler: nil)
    }
}

private struct WebNoteView: NSViewRepresentable {
    @ObservedObject var notes: NotesStore
    let noteKey: String
    var title: String?
    let bridge: WebNoteBridge

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "notes")

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
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WebNoteView
        var currentKey: String = ""
        var loaded = false
        init(_ parent: WebNoteView) { self.parent = parent }

        // JS → Swift: the doc changed. The payload carries the key it belongs to,
        // so an edit that arrives after a note switch still saves to its own note.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "notes", let body = message.body as? [String: Any],
                  let text = body["text"] as? String, let key = body["key"] as? String else { return }
            // Only the open note's title is current; a late edit keeps its own.
            let title = key == currentKey ? parent.title : parent.notes.note(for: key)?.title
            parent.notes.setText(text, for: key, title: title)
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

    private static func jsonString(_ s: String) -> String {
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
          .cm-content { max-width:820px; }
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
        </style>
        <script>\(bundle)</script>
        </head><body>
        <div id="editor"></div>
        <script> PUPNotes.initEditor(\(jsonString(initial)), \(jsonString(key))); </script>
        </body></html>
        """
    }
}
