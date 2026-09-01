import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

/// The notes editor, web-based (CodeMirror 6 + KaTeX, bundled offline). This is
/// how Obsidian works: `$$…$$` / `$…$` render inline live as you type — no click —
/// and moving the caret into a math span reveals its source to edit. The sidebar
/// (vault, schedule) stays native; only this pane is a `WKWebView`.
///
/// Formatting commands no longer live here — they moved into the floating
/// deck (`Views/AssistantFloating.swift`, wayfinder ticket #7) so the note
/// canvas isn't sharing space with a static toolbar strip. `bridge` is passed
/// in from outside (`appState.noteBridge`) rather than owned here, so the
/// deck can drive the same `WKWebView` this view renders.
///
/// Text flows back to `NotesStore` over a script-message bridge; note switches push
/// content in via `setContent`. The note's stored text is always plain Markdown.
struct WebNoteEditor: View {
    @ObservedObject var notes: NotesStore
    @ObservedObject var preferences: Preferences
    let noteKey: String
    var title: String? = nil
    let bridge: WebNoteBridge
    var onOpenNote: ((String) -> Void)? = nil

    @Environment(\.palette) private var palette

    /// Belt-and-suspenders for the AI "Structure"/"Create" prompt rules: a
    /// model that wraps its whole reply in an outer ```markdown fence and
    /// forgets the closing ``` breaks every line after it once inserted —
    /// confirmed live — the editor renders the rest of the note as one giant
    /// unterminated code block. Only strips an explicit `markdown`/`md`
    /// opener, never a bare ```, so a reply that's genuinely just a code
    /// sample (a legitimate use of "Answer"/custom mode) is left alone.
    static func strippingOuterMarkdownFence(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces).lowercased(),
              first == "```markdown" || first == "```md"
        else { return text }
        lines.removeFirst()
        if let lastIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[lastIndex].trimmingCharacters(in: .whitespaces) == "```" {
            lines.remove(at: lastIndex)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        WebNoteView(notes: notes, preferences: preferences, noteKey: noteKey, title: title, bridge: bridge, onOpenNote: onOpenNote)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(palette.accent)
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
    @ObservedObject var preferences: Preferences
    let noteKey: String
    var title: String?
    let bridge: WebNoteBridge
    var onOpenNote: ((String) -> Void)? = nil
    @Environment(\.palette) private var palette

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "notes")
        config.userContentController.add(context.coordinator, name: "open")
        config.userContentController.add(context.coordinator, name: "image")
        config.userContentController.add(context.coordinator, name: "ai")
        // Drag-resized reading column (editor.js's resize handles) echoes
        // its width back so it persists, same shape as every other message.
        config.userContentController.add(context.coordinator, name: "width")
        // loadHTMLString(baseURL: nil) can't reach file://, so pasted/dropped
        // images round-trip through this custom scheme instead.
        config.setURLSchemeHandler(PupImageSchemeHandler(), forURLScheme: "pupimg")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        bridge.webView = webView
        context.coordinator.currentKey = noteKey
        context.coordinator.loaded = false
        webView.loadHTMLString(
            Self.html(initial: notes.text(for: noteKey), key: noteKey, palette: palette, readingWidth: preferences.noteReadingWidth),
            baseURL: nil
        )
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
        // Turning the assistant off in Settings kills the pill live, without
        // requiring the note to be reopened.
        if context.coordinator.loaded, context.coordinator.lastPushedAIEnabled != preferences.aiEnabled {
            context.coordinator.pushAIEnabled(to: webView)
        }
        // Switching the app theme in Settings restyles the whole editor live
        // too — otherwise an already-open note keeps whatever room it loaded
        // with. `palette` is `Equatable`, so this only fires on a real switch.
        if context.coordinator.loaded, context.coordinator.lastPushedPalette != palette {
            context.coordinator.pushPalette(palette, to: webView)
        }
        // Same for switching Sweep/Word blink in Settings.
        if context.coordinator.loaded, context.coordinator.lastPushedRevealMode != preferences.aiRevealAnimation {
            context.coordinator.pushRevealMode(preferences.aiRevealAnimation, to: webView)
        }
        // Reset-to-default (or another window) moving the width outside what
        // this webview last echoed — drag itself doesn't round-trip through
        // here, `lastPushedReadingWidth` already matches mid-drag.
        if context.coordinator.loaded, context.coordinator.lastPushedReadingWidth != preferences.noteReadingWidth {
            context.coordinator.pushReadingWidth(preferences.noteReadingWidth, to: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "notes")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "open")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "image")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ai")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "width")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WebNoteView
        var currentKey: String = ""
        var loaded = false
        /// Last value pushed to `PUPNotes.setAIEnabled`, so `updateNSView`
        /// (called on every SwiftUI re-render) only actually talks to the
        /// webview when the toggle really changed.
        var lastPushedAIEnabled: Bool?
        /// Same idea for the palette's CSS variables, pushed on a theme switch.
        var lastPushedPalette: Palette?
        /// Same idea for Sweep vs. Word blink, pushed on a Settings switch.
        var lastPushedRevealMode: AIRevealAnimation?
        /// Same idea for the reading column's width — also updated the
        /// instant a drag reports back, so `updateNSView`'s own comparison
        /// doesn't immediately re-push the value the webview just sent.
        var lastPushedReadingWidth: Double?
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
            case "ai":
                handleAI(body, webView: message.webView)
            case "width":
                guard let px = body["px"] as? Double else { return }
                parent.preferences.setNoteReadingWidth(px)
                lastPushedReadingWidth = parent.preferences.noteReadingWidth
            default:
                break
            }
        }

        /// The selection-popup's request: `id` round-trips so a stale answer
        /// (from a request the user has since abandoned) can't overwrite a
        /// newer one — `editor.js`'s `aiResult` already checks it too.
        private func handleAI(_ body: [String: Any], webView: WKWebView?) {
            guard let webView, let id = body["id"] as? Int, let mode = body["mode"] as? String,
                  let text = body["text"] as? String else { return }
            let prompt = body["prompt"] as? String

            guard parent.preferences.aiEnabled, !parent.preferences.aiModel.isEmpty else {
                deliver(webView, id: id, text: nil, error: "Turn on IntAssis in Settings first.")
                return
            }
            let instruction: String
            switch mode {
            case "summarize": instruction = Self.summarizeInstruction
            case "answer": instruction = Self.answerInstruction
            case "structure": instruction = Self.structureInstruction
            default: instruction = prompt ?? Self.summarizeInstruction
            }
            let model = parent.preferences.aiModel
            Task {
                guard await LlamaRuntime.ensureChatServer(modelID: model) else {
                    deliver(webView, id: id, text: nil, error: LlamaCppClient.ClientError.offline.errorDescription)
                    return
                }
                do {
                    let result = try await Preferences.localAIClient(modelID: model).generate(
                        model: model, selection: text, instruction: instruction,
                        contextSize: parent.preferences.aiContextSize
                    )
                    deliver(webView, id: id, text: WebNoteEditor.strippingOuterMarkdownFence(result), error: nil)
                } catch {
                    deliver(webView, id: id, text: nil, error: error.localizedDescription)
                }
            }
        }

        private func deliver(_ webView: WKWebView, id: Int, text: String?, error: String?) {
            let textJS = text.map(WebNoteView.jsonString) ?? "null"
            let errorJS = error.map(WebNoteView.jsonString) ?? "null"
            webView.evaluateJavaScript("PUPNotes.aiResult(\(id), \(textJS), \(errorJS));", completionHandler: nil)
        }

        func pushAIEnabled(to webView: WKWebView) {
            lastPushedAIEnabled = parent.preferences.aiEnabled
            webView.evaluateJavaScript("PUPNotes.setAIEnabled(\(parent.preferences.aiEnabled));", completionHandler: nil)
        }

        /// Pushes every theme-derived CSS variable in one round trip — the
        /// popup/editor shapes don't change with theme, just these tokens.
        func pushPalette(_ palette: Palette, to webView: WKWebView) {
            lastPushedPalette = palette
            let root = "document.documentElement"
            let js = WebNoteView.paletteTokens(palette).map { name, value in
                "\(root).style.setProperty('\(name)', \(WebNoteView.jsonString(value)));"
            }.joined()
            webView.evaluateJavaScript(
                "\(root).dataset.scheme = \(WebNoteView.jsonString(WebNoteView.isDark(palette) ? "dark" : "light")); \(js)",
                completionHandler: nil
            )
        }

        func pushRevealMode(_ mode: AIRevealAnimation, to webView: WKWebView) {
            lastPushedRevealMode = mode
            webView.evaluateJavaScript("PUPNotes.setAIRevealMode(\(WebNoteView.jsonString(mode.rawValue)));", completionHandler: nil)
        }

        func pushReadingWidth(_ width: Double, to webView: WKWebView) {
            lastPushedReadingWidth = width
            webView.evaluateJavaScript("PUPNotes.setReadingWidth(\(width));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            pushAIEnabled(to: webView)
            pushRevealMode(parent.preferences.aiRevealAnimation, to: webView)
            lastPushedPalette = parent.palette // already baked into the loaded HTML
            lastPushedReadingWidth = parent.preferences.noteReadingWidth // ditto
        }

        private static let summarizeInstruction = """
        Summarize the following text from a student's notes, in a few short \
        sentences. Reply with the summary only — no preamble.
        """
        private static let answerInstruction = """
        The following text is a question from a student's notes. Answer it. \
        Reply with the answer only — no preamble, no restating the question.
        """

        /// Reformats without paraphrasing away real content — the app's editor
        /// (`notes-editor/src/editor.js`) understands a specific Markdown
        /// dialect, so this spells out exactly that syntax rather than saying
        /// "use Markdown" and hoping the model picks compatible syntax on its
        /// own (nothing here renders in-app if it doesn't match). The layout
        /// itself is spelled out too, not just the syntax — "make it neater"
        /// alone tends to come back as the same prose with a stray heading
        /// slapped on top; a concrete document shape is what actually produces
        /// something scannable.
        private static let structureInstruction = """
        Reorganize the following note text into a tight technical reference —
        same information, denser and easier to scan. Do not remove or invent
        facts; restructure and tighten the wording only.

        Shape it in this order, skipping whatever doesn't apply:
        1. One `#` title only if the note covers a single clear topic — skip
           it entirely for a short fragment or a loose list of facts.
        2. `##` for each major section, `###` for a subsection inside it.
           Two levels deep, never three — split into another `##` section
           instead of nesting further.
        3. Open each section with the core fact or definition in one tight
           sentence before any supporting detail — the takeaway first, not
           built up to.
        4. Enumerable facts (steps, properties, comparisons) become a `- ` or
           `1. ` list, one fact per line — never a paragraph restating them
           in prose.
        5. `**bold**` only on a term's first real use, never as decoration on
           ordinary words. No italics unless a word is genuinely emphasized.
        6. `> ` only for something that actually needs to stand apart (a
           warning, a formula's meaning, an exam note) — not for ordinary
           content.
        7. `$$...$$` for a standalone math expression, `$...$` for inline
           math — only where math is actually present.

        If any actual code appears anywhere in the text, isolate just those
        lines into their own fenced block — ```language on its own line, the
        code, then ``` on its own line — tagged with the specific language
        it's actually written in (python, javascript, typescript, cpp, c,
        java, rust, go, html, css, json, sql, php, or xml). Everything around
        the code (explanation, headings, prose) stays outside the fence as
        normal Markdown text. Never wrap the whole note, or any non-code
        prose, inside a code block just because part of it contains code.

        Cut filler outright: no "In this section...", no restating a heading
        in its own first sentence, no hedging ("it seems", "basically"), no
        closing summary that repeats what was just said. One blank line
        between blocks, nothing padded.

        Reply with the restructured note text only — no preamble, no
        explanation of what changed, no code fences around the whole answer.
        Confirmed live: a model that wraps the whole reply in an outer
        ```markdown fence sometimes never closes it, which breaks every line
        after it once inserted — the fenced-code rule above is only for
        actual code found inside the note, never for the reply as a whole.
        """
    }

    // MARK: HTML shell

    private static let bundle: String? = {
        guard let url = Bundle.main.url(forResource: "notes-editor.bundle", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    private static func jsonString(_ s: String) -> String { jsNoteString(s) }

    /// Light or dark box for the editor's own `[data-scheme]` CSS rules
    /// (`editor.css`) — driven by the *palette*, not the OS, so a room like
    /// Astra Moon reads dark inside the note even when macOS itself is set
    /// to Light. `legibleForeground` already answers "is this background
    /// dark or light" via its luminance check; `.white` means dark ground.
    private static func isDark(_ palette: Palette) -> Bool {
        Color.legibleForeground(on: palette.canvasTop).hex == "#FFFFFF"
    }

    /// Every CSS variable the editor's chrome needs from the current room.
    /// Only `--accent` and `--fg` are genuinely per-palette values — the code
    /// box, borders, and syntax-token colors are two fixed sets in
    /// `editor.css`, selected by the `data-scheme` attribute `pushPalette`
    /// sets alongside these.
    private static func paletteTokens(_ palette: Palette) -> [(String, String)] {
        [
            ("--accent", palette.accent.hex ?? "#5865f2"),
            ("--fg", Color.legibleForeground(on: palette.canvasTop).hex ?? "#1a1a1a"),
        ]
    }

    private static func html(initial: String, key: String, palette: Palette, readingWidth: Double) -> String {
        guard let bundle else {
            return "<html><body style=\"font-family:-apple-system;padding:16px;color:#900\">Notes editor bundle missing.</body></html>"
        }
        // The rest of the editor's CSS (wayfinder ticket #11) moved to
        // `notes-editor/src/editor.css`, injected by `initEditor()` itself —
        // only the tokens that need a per-launch Swift value stay inline
        // here, keyed off `[data-scheme]` rather than `prefers-color-scheme`
        // so the six theme rooms drive the code box, not the OS setting.
        let tokenCSS = paletteTokens(palette).map { "\($0):\($1);" }.joined()
        return """
        <!DOCTYPE html><html data-scheme="\(isDark(palette) ? "dark" : "light")"><head><meta charset="utf-8">
        <style>
          :root {
            color-scheme: light dark; \(tokenCSS) --note-width:\(readingWidth)px;
            /* Monochrome fractal noise; mix-blend-mode does the theme-tinting
               (see .pup-fade-word::before in editor.css) rather than needing
               a per-theme asset. */
            --pup-noise: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
          }
        </style>
        <script>\(bundle)</script>
        </head><body>
        <div id="editor"></div>
        <script> PUPNotes.initEditor(\(jsonString(initial)), \(jsonString(key))); </script>
        </body></html>
        """
    }
}
