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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if session.isOpen {
                AssistantChat(appState: appState, preferences: preferences, session: session)
                    .frame(width: 360, height: 440)
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
        .help("Assistant")
    }
}

/// The expanded panel: transcript, input, and — outside `.auto` — a row per
/// action waiting on the user before it runs.
private struct AssistantChat: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @ObservedObject var session: AssistantSession
    @Environment(\.palette) private var palette
    @FocusState private var inputFocused: Bool
    @State private var input = ""
    /// Keyboard-highlighted row in the command autocomplete palette below —
    /// Tab/↵ complete this one, ↑/↓ move it.
    @State private var highlightedSuggestion = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if !session.pendingActions.isEmpty { pendingActionsList }
            if let error = session.lastError { errorLine(error) }
            Divider()
            inputBar
        }
        .glassPanel(cornerRadius: 20)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Assistant").font(Theme.Typo.detailTitle)
                Spacer()
                Text(preferences.aiPermission.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                        Text("Ask about your notes, schedule, or grades. Or try /read, /summary, /create, /help.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(Array(session.transcript.enumerated()), id: \.offset) { index, turn in
                        bubble(turn).id(index)
                    }
                    if session.isThinking {
                        ProgressView().controlSize(.small).padding(.top, 4)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo(session.transcript.count - 1, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Message bubbles are content, not chrome — no glass on these, per the
    /// app's one hard rule about where Liquid Glass belongs.
    private func bubble(_ turn: AssistantTurn) -> some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if turn.role == .assistant { Spacer(minLength: 24) }
                Text(turn.content)
                    .font(.callout)
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
    private func sourceChips(_ sources: [String]) -> some View {
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

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !commandSuggestions.isEmpty {
                commandPalette
                Divider()
            } else if let hint = activeCommandHint {
                commandHintLine(hint)
            }
            HStack(spacing: 8) {
                TextField("Ask the assistant… or /command", text: $input, axis: .vertical)
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
                    to: text, history: priorHistory, context: context, permission: permission
                )
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
            preferences: preferences
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
        return AssistantContext(
            destination: appState.selection,
            openNoteKey: appState.openNoteKey,
            openNoteText: noteText,
            todayClasses: todayClasses,
            gradesSummary: gradesSummary,
            pinnedNote: session.pinnedNote
        )
    }
}
