import SwiftUI
import Inject

/// The app's one piece of floating chrome that isn't `NavIsland` — bottom-left,
/// reachable from every screen. One glass surface that morphs between shapes
/// rather than several overlapping views (`matchedGeometryEffect(id:
/// "assistant", ...)`, the same vocabulary `NavIsland` uses for its own
/// centre↔top morph):
///
/// - **orb** — idle, everywhere except an open note.
/// - **orb + hover rail** — hovering the orb (wayfinder ticket #8,
///   https://github.com/cGradying/IntPortal/issues/8) grows it sideways into
///   2 page-specific quick actions ("jump + narrate": switch screen if
///   needed, open chat, run the matching command immediately). Clicking the
///   orb itself — not a rail icon — always opens plain chat, same as before.
/// - **toolbar** — Notebook, Vault tab: the note-formatting commands that used
///   to be `WebNoteEditor`'s own static top strip (wayfinder ticket #7,
///   https://github.com/cGradying/IntPortal/issues/7 — prototyped and
///   confirmed live before this landed).
/// - **chat** — tapped open, unchanged from before this ticket.
///
/// Prototype finding worth keeping: a `matchedGeometryEffect`-driven morph
/// needs the state change wrapped in an explicit `withAnimation` (`go`
/// below) — the implicit `.animation(_:value:)` modifier alone reads as a
/// snap even though it's attached correctly, and each branch needs its own
/// `.transition(.opacity)` so content cross-fades instead of popping.
struct AssistantFloating: View {
    @ObserveInjection var inject
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    // Must be its own @ObservedObject, not a computed `appState.assistant` —
    // AppState holds it as a plain `let`, not `@Published`, so SwiftUI never
    // subscribes to AssistantSession's own publisher through a computed
    // pass-through. A click flipped isOpen in memory correctly; nothing ever
    // re-rendered to show it, until something else (any AppState/Preferences
    // @Published change, e.g. the Settings toggle) forced a re-render anyway
    // and picked up the stale-but-correct value. Real bug, not a hunch —
    // traced from the user's exact repro ("only opens when I touch Settings").
    @ObservedObject var session: AssistantSession
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph
    @State private var showLanguages = false
    @State private var showColors = false
    @State private var customColor: Color = .red
    /// Debounced hover state driving `.orbHovered` — see `scheduleHover`.
    @State private var railExpanded = false
    /// Invalidates a pending debounced hover toggle when a newer one
    /// supersedes it (mouse left then re-entered before the leave timer fired).
    @State private var hoverGeneration = 0

    private enum DeckState: Equatable {
        case hidden   // AI off and not on an open note — nothing floats.
        case orb
        case orbHovered
        case toolbar
        case chat
    }

    private var deckState: DeckState {
        if preferences.aiEnabled, session.isOpen { return .chat }
        // Vault tab specifically — Quizzes has no `WebNoteEditor` to drive.
        if appState.selection == .today, appState.notebook.tab == .vault { return .toolbar }
        guard preferences.aiEnabled else { return .hidden }
        return railExpanded ? .orbHovered : .orb
    }

    var body: some View {
        Group {
            switch deckState {
            case .hidden:
                EmptyView()
            case .orb:
                orb.transition(Self.morphTransition)
            case .orbHovered:
                orbWithRail.transition(Self.morphTransition)
            case .toolbar:
                toolbarDeck.transition(Self.morphTransition)
            case .chat:
                AssistantChat(appState: appState, preferences: preferences, session: session, morph: morph)
                    .frame(width: preferences.assistantPanelWidth, height: preferences.assistantPanelHeight)
                    .matchedGeometryEffect(id: "assistant", in: morph)
                    .transition(Self.morphTransition)
            }
        }
        .animation(Motion.island(reduced: reduceMotion), value: deckState)
        // Attached at this level (not inside `orb`/`orbWithRail` individually)
        // so hovering never drops mid-expand when the two views swap out
        // under the pointer. Ignored outside the orb states — the toolbar
        // and chat panel have their own content to hover.
        .onHover { inside in
            guard deckState == .orb || deckState == .orbHovered else { return }
            scheduleHover(inside)
        }
        .enableInjection()
    }

    /// 120ms to expand (ignores a cursor just passing over), 300ms grace to
    /// collapse (survives the pointer moving from the orb toward a rail
    /// icon). `hoverGeneration` cancels a stale timer: re-entering during the
    /// collapse grace invalidates the pending `false`, so the rail never
    /// flickers shut and immediately back open.
    private func scheduleHover(_ hovering: Bool) {
        hoverGeneration += 1
        let generation = hoverGeneration
        let delay = hovering ? 0.12 : 0.30
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard generation == hoverGeneration else { return }
            withAnimation(Motion.island(reduced: reduceMotion)) { railExpanded = hovering }
        }
    }

    /// Anchored at the deck's own bottom-leading corner (where it's pinned in
    /// `PUPSISPortalApp.swift`) — content scales in/out from that corner
    /// while `matchedGeometryEffect` resizes the shared capsule, so the
    /// whole thing reads as one shape expanding/compressing rather than a
    /// flat crossfade in place. Confirmed live: crossfade-only was the
    /// original prototype and read as "the UI fades" rather than "the UI
    /// grows/shrinks" — this is the fix.
    private static let morphTransition: AnyTransition = .scale(scale: 0.82, anchor: .bottomLeading).combined(with: .opacity)

    private func go(open: Bool) {
        withAnimation(Motion.island(reduced: reduceMotion)) { session.isOpen = open }
    }

    private var orb: some View {
        Button { go(open: true) } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .glassInteractive(in: Circle())
        // Confirmed live: `.regularMaterial`'s translucent fallback reads as
        // a near-invisible white-on-white circle against a light canvas
        // (PUP Maroon, Ivory, Sakura). A defined edge, not a shadow, is what
        // the zero-drop-shadow doctrine allows here.
        .overlay(Circle().strokeBorder(palette.accent.opacity(0.35), lineWidth: 1))
        .matchedGeometryEffect(id: "assistant", in: morph)
        .help("IntAssis")
    }

    // MARK: Hover rail (orb states, not Notebook/Vault)
    //
    // "Jump + narrate": clicking a rail item switches to the page it's
    // about (a no-op if already there), opens chat, and runs the matching
    // deterministic slash command (`AssistantCommand`, same parser/runner
    // `AssistantChat.send()` already uses for typed commands) — so the
    // answer appears the same way it would if the user had typed and sent
    // it themselves, just pre-asked.

    private struct RailItem: Identifiable {
        let id: String
        let symbol: String
        let help: String
        let command: String
        /// Where "Next class" etc. actually lives, regardless of which page
        /// the rail itself is showing on — e.g. Notebook's "Next class" jumps
        /// to Schedule; Schedule's own items stay on Schedule.
        let destination: Destination
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var railItems: [RailItem] {
        let today = Self.isoDay.string(from: appState.now)
        let nextClass = RailItem(
            id: "next", symbol: "calendar.badge.clock", help: "Next class",
            command: "/date \(today)", destination: .schedule
        )
        switch appState.selection {
        case .schedule:
            return [
                nextClass,
                RailItem(id: "week", symbol: "calendar", help: "This week", command: "/week", destination: .schedule),
            ]
        case .grades:
            return [
                RailItem(id: "gpa", symbol: "chart.line.uptrend.xyaxis", help: "GPA trend", command: "/grades", destination: .grades),
                nextClass,
            ]
        case .today:
            // Reached only outside the Vault tab (`.toolbar` wins there) —
            // Quizzes, or no note open.
            return [
                RailItem(id: "notes", symbol: "magnifyingglass", help: "List notes", command: "/notes", destination: .today),
                nextClass,
            ]
        }
    }

    /// Switches to the rail item's screen (no-op if already there), then
    /// opens chat and queues its command — `AssistantChat.runPendingCommand`
    /// sends it the moment the panel appears.
    private func jumpAndNarrate(_ item: RailItem) -> some View {
        Button {
            withAnimation(Motion.island(reduced: reduceMotion)) {
                appState.selection = item.destination
                session.isOpen = true
            }
            session.pendingCommand = item.command
        } label: {
            Image(systemName: item.symbol).frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(item.help)
    }

    private var orbWithRail: some View {
        HStack(spacing: 4) {
            // Orb face stays a plain open-chat button, not a rail item —
            // hovering reveals shortcuts, but clicking the orb itself is
            // always "just open chat", same as the plain `.orb` state.
            Button { go(open: true) } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Divider().frame(height: 14)
            ForEach(railItems) { item in
                jumpAndNarrate(item)
            }
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassInteractive(in: Capsule())
        .overlay(Capsule().strokeBorder(palette.accent.opacity(0.35), lineWidth: 1))
        .matchedGeometryEffect(id: "assistant", in: morph)
    }

    // MARK: Toolbar deck (Notebook, Vault tab)
    //
    // Every command below is unchanged from `WebNoteEditor`'s old static
    // toolbar — same `AssistantEngine`-agnostic `WebNoteBridge.cmd(...)`
    // calls, just relocated into this floating deck and driven through
    // `appState.noteBridge` (one shared bridge, mirrored the same way
    // `appState.openNoteKey` already tracks "the note you're looking at")
    // instead of a `@StateObject` local to whichever `WebNoteEditor` happened
    // to be on screen.
    //
    // Ticket #9 ("Where the toolbar commands go") settled both open
    // questions left over from #7: all 19 commands always show (the deck
    // floats over the canvas rather than sharing its width, so there's no
    // real pressure to hide any on focus), and a window too narrow for one
    // row wraps to two via `FlowLayout` rather than scrolling or clipping.
    // `560` is an estimate of the full row's natural width (roughly 18
    // buttons/menus × ~20pt + 3 dividers + padding), not a measured
    // constant — it's a *ceiling*, not a target: `.frame(maxWidth:)` only
    // constrains, so on any window wider than that the row still reports
    // its own smaller intrinsic width rather than stretching to fill it.
    private static let toolbarWidthCeiling: CGFloat = 560

    private var toolbarDeck: some View {
        FlowLayout(spacing: 1, lineSpacing: 3) {
            headingMenu
            divider
            button("bold", "Bold", shortcut: "b") { appState.noteBridge.cmd("bold") }
            button("italic", "Italic", shortcut: "i") { appState.noteBridge.cmd("italic") }
            button("strikethrough", "Strikethrough", shortcut: "x", modifiers: [.command, .shift]) {
                appState.noteBridge.cmd("strike")
            }
            button("highlighter", "Highlight", shortcut: "h", modifiers: [.command, .shift]) {
                appState.noteBridge.cmd("highlight")
            }
            colorButton
            codeButton
            button("x.squareroot", "Math") { appState.noteBridge.cmd("math") }
            button("function", "LaTeX document") { appState.noteBridge.cmd("latexdoc") }
            divider
            button("list.bullet", "Bullet list") { appState.noteBridge.cmd("bullet") }
            button("list.number", "Numbered list") { appState.noteBridge.cmd("numbered") }
            button("checklist", "Checklist") { appState.noteBridge.cmd("checklist") }
            button("text.quote", "Quote") { appState.noteBridge.cmd("quote") }
            button("minus", "Divider") { appState.noteBridge.cmd("rule") }
            button("tablecells", "Table") { appState.noteBridge.cmd("table") }
            divider
            button("photo", "Insert image…") { pickImage() }
            button("link", "Link", shortcut: "k") { appState.noteBridge.cmd("link") }
            button("link.badge.plus", "Link to another note") { appState.noteBridge.cmd("wikilink") }
            if let options = appState.noteAddDateOptions {
                divider
                dateMenu(options)
            }
            if preferences.aiEnabled {
                divider
                Button { go(open: true) } label: {
                    Image(systemName: "sparkles").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.accent)
                .help("IntAssis")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: Self.toolbarWidthCeiling)
        // Horizontal: let the ceiling above (or a narrower window) drive
        // wrapping. Vertical: hug exactly the 1 or 2 rows that produces —
        // an outer `maxHeight: .infinity` alignment frame elsewhere would
        // otherwise stretch this the same way the old unconstrained
        // `ScrollView` stretched horizontally (see WebNoteEditor history).
        .fixedSize(horizontal: false, vertical: true)
        .glassInteractive(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .matchedGeometryEffect(id: "assistant", in: morph)
    }

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

    private func dateMenu(_ options: (next: String, today: String)) -> some View {
        Menu {
            Button("Next class · \(options.next)") { appState.noteBridge.cmd("datestamp", options.next) }
            if options.today != options.next {
                Button("Today · \(options.today)") { appState.noteBridge.cmd("datestamp", options.today) }
            }
        } label: {
            Image(systemName: "calendar.badge.plus").frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.borderless)
        .menuIndicator(.hidden).fixedSize().help("Add dated entry")
    }

    private var headingMenu: some View {
        Menu {
            Button("Heading 1") { appState.noteBridge.cmd("heading", "1") }
            Button("Heading 2") { appState.noteBridge.cmd("heading", "2") }
            Button("Heading 3") { appState.noteBridge.cmd("heading", "3") }
            Divider()
            Button("Normal text") { appState.noteBridge.cmd("heading", "0") }
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
                            appState.noteBridge.cmd("color", c.hex)
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
                            appState.noteBridge.cmd("color", String(hex.dropFirst())) // strip '#'
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
        appState.noteBridge.insertImage(inserted)
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
                            appState.noteBridge.cmd("codeblock", lang.id)
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

    /// `shortcut` covers the handful of commands with a universal text-editor
    /// convention (bold/italic/strike/highlight/link) — block-level commands
    /// (headings, lists, table, image, quote, rule, math, date) have no such
    /// convention and stay mouse-only. Scoped for free: the shortcut only
    /// fires while its `Button` is actually in the tree, i.e. only while the
    /// toolbar deck is showing (Notebook, Vault tab) — nowhere else.
    private func button(
        _ symbol: String, _ help: String,
        shortcut: KeyEquivalent? = nil, modifiers: EventModifiers = .command,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(shortcut.map { "\(help) (\(Self.shortcutLabel($0, modifiers)))" } ?? help)
        .modify(shortcut) { view, key in view.keyboardShortcut(key, modifiers: modifiers) }
    }

    /// Apple's own modifier ordering: ⌃⌥⇧⌘, key last.
    private static func shortcutLabel(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + String(key.character).uppercased()
    }
}

private extension View {
    /// Conditionally applies `transform` only when `value` is non-nil —
    /// `.keyboardShortcut` needs an actual `KeyEquivalent`, not an optional one.
    @ViewBuilder
    func modify<T>(_ value: T?, _ transform: (Self, T) -> some View) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

/// The expanded panel: transcript, input, and — outside `.auto` — a row per
/// action waiting on the user before it runs.
private struct AssistantChat: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @ObservedObject var session: AssistantSession
    let morph: Namespace.ID
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @State private var input = ""
    /// Keyboard-highlighted row in the command autocomplete palette below —
    /// Tab/↵ complete this one, ↑/↓ move it.
    @State private var highlightedSuggestion = 0
    /// Panel size captured at the start of a resize drag, so the grip
    /// accumulates from a fixed point rather than re-reading the (already
    /// mutating) preference mid-drag.
    @State private var sizeAtDragStart: CGSize?
    @State private var gripHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if !session.pendingActions.isEmpty {
                pendingActionsList
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let error = session.lastError {
                errorLine(error)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Divider()
            inputBar
        }
        .glassPanel(cornerRadius: 20)
        .overlay(alignment: .topTrailing) { resizeGrip }
        .animation(Motion.arrival(reduced: reduceMotion), value: session.pendingActions.isEmpty)
        .animation(Motion.arrival(reduced: reduceMotion), value: session.lastError)
        .onAppear {
            inputFocused = true
            runPendingCommand()
        }
        .onChange(of: session.pendingCommand) { _, _ in runPendingCommand() }
    }

    /// A small handle poking past the panel's own top-trailing corner —
    /// offset clear of the header's close/clear buttons rather than sharing
    /// their corner. Dragging widens/heightens; a click that never moved
    /// writes nothing, matching the block-resize convention in `Blocks.swift`.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(gripHovered ? palette.accent : .secondary.opacity(0.5))
            .padding(6)
            .contentShape(Rectangle())
            .offset(x: 6, y: -6)
            .onHover { inside in
                gripHovered = inside
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = sizeAtDragStart ?? CGSize(
                            width: preferences.assistantPanelWidth,
                            height: preferences.assistantPanelHeight
                        )
                        if sizeAtDragStart == nil { sizeAtDragStart = start }
                        // Anchored bottom-leading: dragging right widens, dragging
                        // *up* (negative dy) heightens.
                        preferences.setAssistantPanelSize(CGSize(
                            width: start.width + value.translation.width,
                            height: start.height - value.translation.height
                        ))
                    }
                    .onEnded { _ in sizeAtDragStart = nil }
            )
            .onTapGesture(count: 2) { preferences.resetAssistantPanelSize() }
            .help("Drag to resize · double-click to reset")
    }

    /// Whether the "what can you do" popover is showing — local, not on
    /// `session`, since it's transient UI state nothing else needs to see.
    @State private var showingCapabilities = false
    /// Whether the thinking popover is showing — same reasoning as above.
    @State private var showingThinking = false

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("IntAssis").font(typography.detailTitle)
                Button { showingCapabilities = true } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("What can I ask it to do?")
                .popover(isPresented: $showingCapabilities, arrowEdge: .bottom) { capabilitiesPopover }
                Button { showingThinking = true } label: {
                    Image(systemName: "brain").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(preferences.aiThinking == .off ? .secondary : palette.accent)
                .help("Thinking: \(preferences.aiThinking.label)")
                .popover(isPresented: $showingThinking, arrowEdge: .bottom) { thinkingPopover }
                Spacer()
                Text(preferences.aiPermission.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !session.transcript.isEmpty {
                    Button { session.reset() } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear conversation")
                }
                Button {
                    session.isOpen = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if let pin = session.pinnedNote {
                pinChip(pin)
            }
        }
        .padding(12)
    }

    /// Read straight off `AssistantTool.catalog` — the same list that builds
    /// the system prompt and the response schema, so this can never drift
    /// from what the model can actually do. Grouped by a plain name prefix
    /// rather than a second category field on `AssistantTool`, which would
    /// be one more thing every future tool has to remember to set.
    private var capabilitiesPopover: some View {
        let groups: [(String, [AssistantTool])] = [
            ("Calendar", AssistantTool.catalog.filter {
                ["read_week", "read_date", "add_event", "move_event", "set_class_status", "set_class_time"].contains($0.name)
            }),
            ("Notes", AssistantTool.catalog.filter { $0.name.hasSuffix("note") || $0.name.hasSuffix("notes") }),
            ("Grades", AssistantTool.catalog.filter { $0.name == "read_grades" }),
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What it can do").font(.headline)
                ForEach(groups, id: \.0) { title, tools in
                    if !tools.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.caption).foregroundStyle(.secondary)
                            ForEach(tools, id: \.name) { tool in capabilityRow(tool) }
                        }
                    }
                }
                Text(preferences.aiPermission == .auto
                     ? "Changes apply right away in \(preferences.aiPermission.label) mode."
                     : "Every change is shown to you first — nothing applies without a tap.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(width: 300, height: 340)
    }

    /// A tool's matching slash command, if one exists — the deterministic
    /// commands are a bypass around the model's own tool-picking, so a
    /// capability with one should be reachable both ways from this popover.
    private static let commandForTool: [String: String] = [
        "read_date": "date", "add_event": "event", "move_event": "move",
        "set_class_status": "vacant", "read_week": "week", "read_grades": "grades",
        "list_notes": "notes", "search_notes": "find", "ask_notes": "rag",
        "read_note": "read", "create_note": "create",
    ]

    /// Read-only text for a capability with no deterministic command
    /// (`set_class_time`, `append_note` — no slash command covers them);
    /// otherwise a button that prefills that command into the input and
    /// closes the popover, so tapping it is the fastest way in.
    private func capabilityRow(_ tool: AssistantTool) -> some View {
        Group {
            if let name = Self.commandForTool[tool.name],
               let spec = AssistantCommand.catalog.first(where: { $0.name == name }) {
                Button {
                    input = spec.params.isEmpty ? "/\(spec.name)" : "/\(spec.name) "
                    showingCapabilities = false
                    inputFocused = true
                } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Text("•").foregroundStyle(.secondary)
                        Text(tool.description).font(.callout).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text(spec.usage).font(.caption2.monospaced()).foregroundStyle(palette.accent)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("• \(tool.description)").font(.callout)
            }
        }
    }

    private func pinChip(_ pin: AssistantCommandRunner.PinnedNote) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill").font(.system(size: 9))
            Text(pin.name).font(.caption2).lineLimit(1)
            Button { session.pinnedNote = nil } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(palette.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(palette.accent)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if session.transcript.isEmpty {
                        Text("Ask what's on a date, mark a class vacant, move an event — or about your notes and grades. Tap the ? above to see everything it can do, or try /week, /find, /event, /help.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        accuracyWarning
                    }
                    ForEach(Array(session.transcript.enumerated()), id: \.offset) { index, turn in
                        bubble(turn, reveal: index == lastAssistantIndex)
                            .id(index)
                            .transition(.opacity.combined(with: .move(edge: turn.role == .user ? .trailing : .leading)))
                    }
                    if session.isThinking {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.arrival(reduced: reduceMotion), value: session.transcript.count)
            }
            .onChange(of: session.transcript.count) { _, _ in
                withAnimation(Motion.arrival(reduced: reduceMotion)) {
                    proxy.scrollTo(session.transcript.count - 1, anchor: .bottom)
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity)
    }

    /// Only the newest reply gets the reveal — re-rendering scrollback (e.g.
    /// after a resize) must never replay old turns' animations.
    private var lastAssistantIndex: Int? {
        session.transcript.lastIndex { $0.role == .assistant }
    }

    /// Three squares blinking in sequence rather than a stock spinner — the
    /// panel's one piece of ambient/waiting motion. Static (fixed opacity)
    /// under Reduce Motion, per the app's contract. At `.max` thinking, the
    /// label itself glitches too — the one place this turn's extra reasoning
    /// depth is visible while it's happening.
    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            PixelThinkingDots(color: palette.accent, reduced: reduceMotion)
            if preferences.aiThinking == .max {
                GlitchGradientText(
                    text: "thinking hard…",
                    font: .caption2,
                    gradient: [palette.accent, palette.accent.opacity(0.5)]
                )
            }
        }
        .padding(.top, 4)
    }

    /// Message bubbles are content, not chrome — no glass on these, per the
    /// app's one hard rule about where Liquid Glass belongs. `reveal` is true
    /// only for the newest assistant turn — a reply arrives as one whole
    /// string (no streaming, see `AssistantEngine.respond`), so this is what
    /// keeps it from just appearing as a wall of text.
    private func bubble(_ turn: AssistantTurn, reveal: Bool) -> some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if turn.role == .assistant { Spacer(minLength: 24) }
                Group {
                    if turn.role == .assistant, reveal, !reduceMotion {
                        RevealText(turn.content)
                    } else if let markdown = try? AttributedString(
                        markdown: turn.content,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(markdown)
                    } else {
                        Text(turn.content)
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(
                    turn.role == .user ? palette.accent.opacity(0.16) : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                if turn.role == .user { Spacer(minLength: 24) }
            }
            if !turn.sources.isEmpty { sourceChips(turn.sources) }
        }
        .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
    }

    /// One capsule per note a `search_notes`/`ask_notes` reply actually drew
    /// from — the "did this come from RAG, and which note" the panel didn't
    /// show before (only a `Sources: …` line buried in the reply text).
    /// Scrolls horizontally rather than wrapping — a plain `HStack` overflowed
    /// the panel width once a reply drew from four or more notes.
    private func sourceChips(_ sources: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(palette.accent)
                ForEach(sources, id: \.self) { name in
                    Text(name)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.leading, 24)
        .help("From your notes: \(sources.joined(separator: ", "))")
    }

    // ponytail: propose and confirm share this same Apply/Skip list for now —
    // the plan's distinction between them ("shows what it would do" vs "each
    // action confirmed") reads the same in a chat UI where nothing runs
    // without a tap either way. Split them if that stops feeling true.
    private var pendingActionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(session.pendingActions.enumerated()), id: \.offset) { index, action in
                actionRow(action, at: index)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func actionRow(_ action: AssistantAction, at index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(palette.accent)
            Text(AssistantTool.named(action.tool)?.description ?? action.tool)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("Skip") { session.pendingActions.remove(at: index) }
                .buttonStyle(.borderless).font(.caption)
            Button("Apply") { apply(action, at: index) }
                .buttonStyle(.borderedProminent).controlSize(.mini)
        }
    }

    private func apply(_ action: AssistantAction, at index: Int) {
        session.pendingActions.remove(at: index)
        Task {
            let executor = makeExecutor()
            let result = await executor.execute(action)
            session.appendAssistant(result.message, sources: result.sources)
        }
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).lineLimit(2)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// Shown once, at the start of the conversation — not dismissible, but
    /// tied to the empty transcript rather than pinned above the input
    /// forever, so it returns every time `session.reset()` clears the chat
    /// without nagging mid-conversation.
    private var accuracyWarning: some View {
        Text("Runs locally and can be wrong. Check anything that matters.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !commandSuggestions.isEmpty {
                commandPalette
                Divider()
            } else if let hint = activeCommandHint {
                commandHintLine(hint)
            }
            HStack(spacing: 8) {
                TextField("Ask IntAssis… or /command", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : palette.accent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isThinking)
            }
            .padding(10)
        }
        // Tab/↵ complete the highlighted row; ↑/↓ move it. All four fall
        // through to .ignored (normal typing / the TextField's own onSubmit)
        // whenever the palette isn't showing.
        .onKeyPress(.tab) { completeHighlighted() }
        .onKeyPress(.return) { completeHighlighted() }
        .onKeyPress(.downArrow) { moveHighlight(1) }
        .onKeyPress(.upArrow) { moveHighlight(-1) }
        .onChange(of: input) { _, _ in highlightedSuggestion = 0 }
    }

    /// Autocomplete while the command word itself is still being typed —
    /// before the first space, so it never fights with typing the argument.
    private var commandSuggestions: [AssistantCommand.Spec] {
        guard input.hasPrefix("/"), !input.contains(" ") else { return [] }
        let typed = input.dropFirst().lowercased()
        guard !typed.isEmpty else { return AssistantCommand.catalog }
        return AssistantCommand.catalog.filter { $0.name.hasPrefix(typed) }
    }

    /// Once the command word is finished (a space typed) and matches a real
    /// command, a one-line reminder of its argument replaces the full list.
    private var activeCommandHint: AssistantCommand.Spec? {
        guard input.hasPrefix("/"), let spaceIndex = input.firstIndex(of: " ") else { return nil }
        let word = input[input.index(after: input.startIndex)..<spaceIndex].lowercased()
        return AssistantCommand.catalog.first { $0.name == word }
    }

    private var commandPalette: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(commandSuggestions.enumerated()), id: \.element.id) { index, spec in
                Button { complete(spec) } label: {
                    HStack(spacing: 6) {
                        Text(spec.usage).font(.caption.monospaced()).fontWeight(.semibold)
                        Text(spec.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(
                        index == highlightedSuggestion ? palette.accent.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
    }

    /// The brain button's popover: the level picker (moved here from an
    /// always-visible bottom bar) plus the last completed turn's actual
    /// reasoning text — the thing that bar never showed at all. Same idea as
    /// Claude's own thinking picker, in this app's glass/pixel idiom: a
    /// segmented row of cells rather than a stock `Picker`. `.max` gets the
    /// app's own ambient glitch treatment (`GlitchGradientText`) as its
    /// "special effect" — reusing the existing Matrix-scramble idiom rather
    /// than inventing a second one.
    private var thinkingPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thinking").font(.headline)
            HStack(spacing: 4) {
                ForEach(AssistantThinking.allCases) { level in
                    thinkingCell(level)
                }
            }
            Text(preferences.aiThinking.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Group {
                if session.lastThinking.isEmpty {
                    Text("No thinking yet — ask something.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(session.lastThinking)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func thinkingCell(_ level: AssistantThinking) -> some View {
        let selected = preferences.aiThinking == level
        return Button { preferences.aiThinking = level } label: {
            Group {
                if selected, level == .max {
                    GlitchGradientText(
                        text: level.label,
                        font: .caption2.weight(.semibold),
                        gradient: [palette.accent, palette.accent.opacity(0.5)]
                    )
                } else {
                    Text(level.label)
                        .font(.caption2.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? palette.accent : .secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(selected ? palette.accent.opacity(0.16) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func commandHintLine(_ spec: AssistantCommand.Spec) -> some View {
        Text("\(spec.usage) — \(spec.description)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 6)
    }

    /// Fills the input with `spec`'s usage — sends immediately for a
    /// no-argument command (nothing left to type), otherwise leaves a
    /// trailing space and keeps editing (that space is also what hides the
    /// palette, since `commandSuggestions` requires no space yet).
    private func complete(_ spec: AssistantCommand.Spec) {
        if spec.params.isEmpty {
            input = "/\(spec.name)"
            send()
        } else {
            input = "/\(spec.name) "
        }
    }

    private func completeHighlighted() -> KeyPress.Result {
        guard !commandSuggestions.isEmpty else { return .ignored }
        complete(commandSuggestions[min(highlightedSuggestion, commandSuggestions.count - 1)])
        return .handled
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        guard !commandSuggestions.isEmpty else { return .ignored }
        let count = commandSuggestions.count
        highlightedSuggestion = ((highlightedSuggestion + delta) % count + count) % count
        return .handled
    }

    /// Runs the deck's hover-rail command, if one is waiting — fired from
    /// both `.onAppear` (rail click opened the panel fresh) and
    /// `.onChange(of: session.pendingCommand)` (panel was already open on
    /// this screen; clicking a rail item queues a second command into it).
    private func runPendingCommand() {
        guard let command = session.pendingCommand else { return }
        session.pendingCommand = nil
        input = command
        send()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isThinking else { return }
        input = ""
        session.lastError = nil
        session.pendingActions = []
        let priorHistory = session.transcript
        session.appendUser(text)

        // Slash-commands never reach the model's tool-picking loop at all —
        // parsed deterministically here, or falls through to the engine below.
        if let command = AssistantCommand.parse(text) {
            session.isThinking = true
            Task {
                let outcome = await makeCommandRunner().run(command)
                if let pin = outcome.pin { session.pinnedNote = pin }
                session.appendAssistant(outcome.reply, sources: outcome.sources)
                session.isThinking = false
            }
            return
        }

        session.isThinking = true

        let engine = makeEngine()
        let context = buildContext()
        let permission = preferences.aiPermission

        Task {
            do {
                let outcome = try await engine.respond(
                    to: text, history: priorHistory, context: context, permission: permission,
                    think: preferences.aiThinking
                )
                session.lastThinking = outcome.thinking
                // `.auto` already executed every tool itself — fold whichever
                // notes it drew from into the reply's own chip, rather than
                // leaving them buried in a mid-loop tool result nobody sees.
                let sources = outcome.results.flatMap(\.sources).reduce(into: [String]()) { unique, name in
                    if !unique.contains(name) { unique.append(name) }
                }
                session.appendAssistant(
                    AssistantSession.displayReply(outcome.reply, actionCount: outcome.actions.count),
                    sources: sources
                )
                if permission != .auto {
                    session.pendingActions = outcome.actions
                }
            } catch {
                session.lastError = error.localizedDescription
            }
            session.isThinking = false
        }
    }

    private func makeCommandRunner() -> AssistantCommandRunner {
        AssistantCommandRunner(
            notes: appState.notes,
            openNoteKey: { appState.openNoteKey },
            model: preferences.aiModel,
            preferences: preferences,
            executor: makeExecutor()
        )
    }

    private func makeExecutor() -> RealAssistantExecutor {
        RealAssistantExecutor(
            notes: appState.notes,
            editor: appState.assistantEditor,
            calendar: appState.calendar,
            portal: appState.portal,
            preferences: preferences,
            openNoteKey: { appState.openNoteKey }
        )
    }

    private func makeEngine() -> AssistantEngine {
        AssistantEngine(model: preferences.aiModel, executor: makeExecutor())
    }

    private func buildContext() -> AssistantContext {
        let today = Weekday.on(appState.now)
        let weekStart = Weekday.weekStart(containing: appState.now)
        let todayClasses = appState.portal.sessions
            .filter { $0.day == today }
            .map { session -> AssistantContext.ClassEntry in
                let time = preferences.time(for: session, on: weekStart)
                return AssistantContext.ClassEntry(session: session, start: time.start, end: time.end)
            }
        let noteText = appState.openNoteKey.map { appState.notes.text(for: $0) }
        let gradesSummary = appState.portal.grades.flatMap { report -> String? in
            guard report.hasPostedGrades else { return nil }
            let gpa = report.computedGPA.map { String(format: "%.2f", $0) } ?? "n/a"
            return "GPA \(gpa) across \(report.subjects.count) subjects"
        }
        let schedule = AssistantScheduleSnapshot(
            now: appState.now,
            sessions: appState.portal.sessions,
            termEnd: preferences.termEndDate,
            status: { preferences.termStatus(for: $0) },
            time: { preferences.termTime(for: $0) }
        )
        // The "shared JSON file" — written once per turn (cheap: a few dozen
        // sessions), same Application Support convention as
        // schedule.json/notes.json. Not load-bearing for the prompt itself
        // (that's `schedule.rendered` below) — this is for inspection.
        schedule.save()
        return AssistantContext(
            destination: appState.selection,
            openNoteKey: appState.openNoteKey,
            openNoteText: noteText,
            todayClasses: todayClasses,
            gradesSummary: gradesSummary,
            schedule: schedule,
            pinnedNote: session.pinnedNote
        )
    }
}

/// A reply fading in word by word instead of appearing as a wall of text —
/// there's no streaming from the model (`AssistantEngine.respond` returns
/// one whole string), so this is the panel's substitute for a typing effect.
/// Plain text, not markdown — the note editor's word-blink reveal
/// (`AIRevealAnimation`) is the precedent for word-granular over character
///-granular. Caller is responsible for skipping this under Reduce Motion.
private struct RevealText: View {
    let text: String
    private let words: [String]
    @State private var shown = 0

    init(_ text: String) {
        self.text = text
        words = text.split(separator: " ").map(String.init)
    }

    var body: some View {
        Text(words.prefix(shown).joined(separator: " "))
            .animation(.easeOut(duration: 0.08), value: shown)
            // `.task(id:)`, not `.onAppear` — an `Int` isn't `VectorArithmetic`,
            // so `withAnimation { shown = words.count }` would just snap
            // between the two endpoints rather than interpolate. Stepping
            // through the words explicitly is what actually reveals them.
            .task(id: text) {
                shown = 0
                guard !words.isEmpty else { return }
                let perWord = min(500_000_000 / UInt64(words.count), 40_000_000) // ns; ≤0.5s total, ≤40ms/word
                for index in 1...words.count {
                    shown = index
                    if index < words.count { try? await Task.sleep(nanoseconds: perWord) }
                }
            }
    }
}

/// Three squares blinking in sequence — the "thinking" indicator, in the
/// app's own pixel idiom instead of a stock `ProgressView`. Reduce Motion
/// holds them at a fixed half-opacity instead of animating.
private struct PixelThinkingDots: View {
    var color: Color
    var reduced: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduced ? nil : 0.35, paused: reduced)) { context in
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = reduced ? 1.0 : blink(context.date, offset: i)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(reduced ? 0.5 : phase))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    /// Cycles 0.25…1…0.25 with a per-dot phase offset, so the three blink in
    /// sequence rather than together.
    private func blink(_ date: Date, offset: Int) -> Double {
        let t = date.timeIntervalSinceReferenceDate / 0.35 + Double(offset) * 0.6
        return 0.625 + 0.375 * sin(t * .pi)
    }
}

/// A left-to-right, top-to-bottom flow: each child at its own intrinsic
/// size, wrapping to a new row once the next one wouldn't fit the proposed
/// width. Used only by `toolbarDeck` (wayfinder ticket #9) so a narrow
/// window wraps its 19 commands to a second row instead of scrolling or
/// running past the edge — everything reachable without a gesture.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widestRow: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widestRow = max(widestRow, x - spacing)
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, x - spacing)
        return CGSize(width: maxWidth.isFinite ? maxWidth : widestRow, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
