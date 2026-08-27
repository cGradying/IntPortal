import SwiftUI

/// The assistant's one piece of floating chrome — bottom-left, reachable from
/// every screen. Idle it's a small orb; tapped it expands into the chat panel.
/// One glass surface that morphs, the same shape `NavIsland` uses for its own
/// home↔bar transition, rather than two separate overlapping glass views —
/// they're never on screen at once, so there's nothing for
/// `GlassEffectContainer` to blend.
struct AssistantFloating: View {
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

    var body: some View {
        Group {
            if session.isOpen {
                AssistantChat(appState: appState, preferences: preferences, session: session, morph: morph)
                    .frame(width: preferences.assistantPanelWidth, height: preferences.assistantPanelHeight)
                    .matchedGeometryEffect(id: "assistant", in: morph)
            } else {
                orb
            }
        }
        .animation(Motion.island(reduced: reduceMotion), value: session.isOpen)
    }

    private var orb: some View {
        Button { session.isOpen = true } label: {
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
        .onAppear { inputFocused = true }
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
