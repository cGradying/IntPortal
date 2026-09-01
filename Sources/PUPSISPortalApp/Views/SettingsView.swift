import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import Inject

struct SettingsView: View {
    @ObserveInjection var inject
    @ObservedObject var appState: AppState
    /// `appState.updaterBridge` is its own `ObservableObject` — this view must
    /// observe it directly, or a version becoming available while Settings is
    /// already open wouldn't repaint the About tab. See `CalendarView`, same reason.
    @ObservedObject var updaterBridge: UpdaterBridge
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var googleAuth: GoogleAuth
    @ObservedObject fileprivate var notifier = Notifier.shared
    /// Held here rather than acted on immediately when a pick would need more
    /// memory than looks available — `.alert(item:)` below asks first.
    @State private var pendingModelLoad: PendingModelLoad?
    /// `nil` when no download is running; 0...1 while `installModel` pulls.
    @State private var installProgress: Double?
    @State private var installingLabel: String?
    @State private var installError: String?
    /// Recomputed after every download — which `ModelCatalog` entries are
    /// actually on disk, driving each row's Download/Selected state.
    @State private var downloadedIDs: Set<String> = []
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// System Reduce Motion, OR'd with General's own "Force Reduce Motion"
    /// toggle. `\.accessibilityReduceMotion` has no public setter in this
    /// SDK — a `.environment(\.accessibilityReduceMotion, _)` override
    /// doesn't reach child views — so the toggle is scoped to this window's
    /// own animations (the RAM warning, a deleted model row), not the whole
    /// app. Tab switching itself is `TabView`'s own native, unanimated-by-us
    /// transition — no `.id()`/`.transition()` on top of it, which is what
    /// made pane switching feel heavy in the sidebar version.
    private var effectiveReduceMotion: Bool { preferences.forceReducedMotion || reduceMotion }
    @State fileprivate var exportResult: String?
    @State fileprivate var googleCalendars: [GoogleCalendar] = []
    @State fileprivate var googleBusy = false
    @State fileprivate var googleResult: String?
    /// Mirrors the OS login-item status; re-read after every toggle so it can't
    /// drift from System Settings.
    @State fileprivate var launchAtLogin = LoginItem.isEnabled
    /// Gates the Misc tab's "Delete All Notes" confirmation dialog.
    @State private var confirmingWipe = false
    /// Gates General's "Reset All Settings…" confirmation dialog.
    @State private var confirmingReset = false
    /// Whether the context-size explainer popover is showing.
    @State private var showingContextInfo = false
    /// A local buffer for the selected provider's API key (wayfinder ticket
    /// #17) — deliberately not a `Preferences` field; it's loaded from/saved
    /// straight to `AIProviderKeyStore` (Keychain), never `UserDefaults`.
    @State private var apiKeyDraft = ""
    /// Data & Storage's file/model sizes, computed off the render path —
    /// see `refreshDiskUsage()`. A synchronous recursive `FileManager` walk
    /// on every body evaluation was a real, measurable lag source.
    @State private var fileSizes: [String: Int64] = [:]
    @State private var modelSizes: [String: Int64] = [:]

    /// Subjects the user can actually recolor: whatever is on screen right now.
    private var subjectCodes: [String] {
        ClassSession.subjectCodes(in: appState.portal.sessions)
    }

    private enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, schedule, notifications, intelligence, dataStorage, account, about
        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .schedule: "Schedule"
            case .notifications: "Notifications"
            case .intelligence: "Intelligence"
            // Short for the tab strip — 8 tabs have real width pressure a
            // vertical list never had. "Data & Storage" elsewhere (the pane's
            // own content) still spells it out.
            case .dataStorage: "Storage"
            case .account: "Account"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintbrush"
            case .schedule: "calendar"
            case .notifications: "bell.badge"
            case .intelligence: "sparkles"
            case .dataStorage: "internaldrive"
            case .account: "person.crop.circle"
            case .about: "info.circle"
            }
        }
    }

    @State private var pane: Pane = .general
    /// Drives the tab indicator line's slide between tabs — same technique
    /// `NavIsland`'s own segment-selection capsule already uses.
    @Namespace private var tabIndicatorNamespace

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
                .padding(.horizontal, 16)
                .padding(.top, 12)
            compactPane { paneContent(for: pane) }
            bottomBar
        }
        .tint(palette.accent)
        .background(palette.canvasWash.ignoresSafeArea())
        .task { await notifier.refreshAuthorization() }
        .task(id: googleAuth.isConnected) {
            if googleAuth.isConnected { await loadGoogleCalendars() }
        }
        .enableInjection()
    }

    /// Replaces `.tabItem`/native `TabView` chrome — macOS exposes no
    /// modifier to resize that strip at all, which is exactly why it read
    /// as too thin. Text-only, no icon: dropping the icon (and its ~20pt of
    /// padding/spacing per tab) is what actually buys 8 tabs enough room to
    /// stay full-size and readable — no `.minimumScaleFactor` shrinking
    /// (confirmed live that reads as broken, and `Label`'s icon+title
    /// composition doesn't reliably honor it anyway), no truncation.
    ///
    /// Selection reads as a thin pixel-dither line under the current tab,
    /// not a full capsule wash — it glides between tabs via
    /// `matchedGeometryEffect` on switch, and idles with the same
    /// wave-dither ambient drift `HomeNoiseField` already uses for the home
    /// launcher (this app's one other continuous ambient loop) rather than
    /// sitting static.
    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(Pane.allCases) { item in
                let selected = pane == item
                Button {
                    withAnimation(Motion.selection(reduced: effectiveReduceMotion)) { pane = item }
                } label: {
                    VStack(spacing: 6) {
                        Text(item.label)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(selected ? palette.accent : .secondary)
                        Group {
                            if selected {
                                TabIndicatorLine(color: palette.accent, reduced: effectiveReduceMotion)
                                    .matchedGeometryEffect(id: "tabIndicator", in: tabIndicatorNamespace)
                            } else {
                                Color.clear.frame(height: 3)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 12)
    }

    /// Replaces the sheet's `.toolbar { ToolbarItem(.confirmationAction) }`
    /// — macOS reserves a full-width band for that placement on a sheet far
    /// taller than one button needs. A plain row gives real height control.
    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Done") { appState.showingSettings = false }
                .glassProminentButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func paneContent(for pane: Pane) -> some View {
        switch pane {
        case .general: generalTab
        case .appearance: appearanceTab
        case .schedule: scheduleTab
        case .notifications: notificationsTab
        case .intelligence: intelligenceTab
        case .dataStorage: dataStorageTab
        case .account: accountTab
        case .about: aboutTab
        }
    }

    // MARK: Compact layout primitives

    /// Replaces `Form`/`.formStyle(.grouped)` — a plain scroll view over a
    /// tight `VStack`, none of `Form`'s generous list-row insets or
    /// grouped-list chrome. Section-to-section rhythm comes from this
    /// `VStack`'s own spacing, not per-section padding.
    private func compactPane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Replaces `Section(header:footer:)` — a small-caps label above a real
    /// glass card (the app's own structural-chrome material, same helper the
    /// nav island and popovers use — `GlassCompat.swift`'s "Chrome-Not-
    /// Decoration Rule": a card grouping settings rows is structure, same
    /// job the island's own panel does), tight rows with hairline
    /// separators, an optional footer caption below.
    private func compactSection<Content: View>(
        _ title: String, footer: String? = nil, @ViewBuilder rows: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(.caption, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) { rows() }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .glassPanel(cornerRadius: 12)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    /// Replaces a bare `Toggle`/`Picker`/`LabeledContent` row — fixed label
    /// left, control right, one consistent row height instead of each
    /// control's own native sizing, a hairline (`palette.gridLine` — the
    /// same token the week grid's own hour rules use) separating it from
    /// the row below. Pass a control with `.labelsHidden()` already applied
    /// (SwiftUI controls draw their own label otherwise, which would repeat
    /// the text this row already shows).
    private func compactRow<Content: View>(_ label: String, @ViewBuilder control: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout).fontWeight(.medium)
            Spacer(minLength: 12)
            control()
        }
        // Without this, each row sizes to its own content's natural width
        // inside compactSection's VStack(alignment: .leading) — a row with
        // wider trailing content (a value + an icon) ends further right
        // than a row with a tight Picker box. Forcing every row to the
        // card's full width is what lets Spacer push every trailing
        // control to the same shared right edge.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.gridLine).frame(height: 1)
        }
    }

    /// Always-visible technical facts for a pane — real paths, identifiers,
    /// and raw statuses, monospaced and selectable.
    private func technicalSection(_ rows: [(String, String)]) -> some View {
        compactSection("Technical Details") {
            ForEach(rows, id: \.0) { row in
                compactRow(row.0) {
                    Text(row.1)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// One row of swatches instead of a label-per-row grid — six themes read
    /// fine as circles alone (the accent color *is* the identity here), so
    /// the name moves to `.help()` rather than costing its own line.
    private var themeSwatchRow: some View {
        HStack(spacing: 10) {
            ForEach(ThemeChoice.allCases) { choice in
                let selected = preferences.theme == choice
                Button { preferences.theme = choice } label: {
                    Circle()
                        .fill(choice.palette(for: systemScheme).accent)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: 2).opacity(selected ? 1 : 0))
                        .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(choice.label)
                .accessibilityLabel(choice.label)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: General

    /// Window/launcher behavior, motion, the notes database location, and
    /// the two destructive resets, last.
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            compactSection("Dynamic Island", footer: "The app's floating top bar, and the red/yellow/green window buttons.") {
                compactRow("Open on the home launcher") {
                    Toggle("", isOn: $preferences.islandStartHome).labelsHidden().toggleStyle(.switch)
                }
                compactRow("Expand island on hover") {
                    Toggle("", isOn: $preferences.islandExpandOnHover).labelsHidden().toggleStyle(.switch)
                }
                compactRow("Auto-hide window buttons") {
                    Toggle("", isOn: $preferences.trafficLightsAutoHide).labelsHidden().toggleStyle(.switch)
                }
                compactRow("Start at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, wants in
                            LoginItem.setEnabled(wants)
                            // Reflect what actually took effect, in case registration failed.
                            launchAtLogin = LoginItem.isEnabled
                        }
                }
            }

            compactSection(
                "Motion",
                footer: "Forces this Settings window's own animations (deleting a model, the RAM warning) to their reduced form, independent of System Settings' own Reduce Motion."
            ) {
                compactRow("Force Reduce Motion") {
                    Toggle("", isOn: $preferences.forceReducedMotion).labelsHidden().toggleStyle(.switch)
                }
            }

            compactSection(
                "Notes Database",
                footer: "Opens Finder with notes.json selected — the file everything in Notes is stored in."
            ) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([NotesStore.defaultURL])
                }
                .glassButton()
                .controlSize(.small)
            }

            Button("Reset This Pane to Defaults") {
                preferences.islandStartHome = true
                preferences.islandExpandOnHover = true
                preferences.trafficLightsAutoHide = true
                preferences.forceReducedMotion = false
            }
            .glassButton()
            .controlSize(.small)

            compactSection(
                "Wipe Notes",
                footer: "Deletes every note, folder, and pasted image. Login, schedule/grades cache, and settings are untouched."
            ) {
                Button("Delete All Notes…", role: .destructive) { confirmingWipe = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .confirmationDialog(
                "Delete all notes?",
                isPresented: $confirmingWipe
            ) {
                Button("Delete Everything", role: .destructive) { appState.notes.wipeAll() }
            } message: {
                Text("This deletes every note, folder, and pasted image. This cannot be undone.")
            }

            compactSection(
                "Danger Zone",
                footer: "Resets every setting in this app — theme, AI configuration, calendar exports, notification preferences, everything each pane's own controls expose — back to first-launch defaults. Per-class colors, online/vacant marks, moved times, notes, and syllabus tasks, plus your schedule cache, notes, and quiz decks, are untouched."
            ) {
                Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .confirmationDialog(
                "Reset all settings?",
                isPresented: $confirmingReset
            ) {
                Button("Reset Everything", role: .destructive) { preferences.resetAllToDefaults() }
            } message: {
                Text("This resets every setting to its default. This cannot be undone.")
            }

            technicalSection([
                ("App Support directory", NotesStore.defaultURL.deletingLastPathComponent().path),
                ("Login item status", "\(SMAppService.mainApp.status)"),
            ])
        }
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            compactSection("Theme") {
                themeSwatchRow
                    .padding(.vertical, 4)
                compactRow("Font") {
                    Picker("", selection: $preferences.fontChoice) {
                        ForEach(FontChoice.allCases) { choice in
                            Text(choice.label)
                                .font(Typography(choice).screenTitle.weight(.regular))
                                .tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                }
                compactRow("UI Scale") {
                    HStack(spacing: 8) {
                        Text("\(Int(preferences.uiScale * 100))%").foregroundStyle(.secondary)
                        Stepper("", value: $preferences.uiScale, in: Preferences.uiScaleRange, step: Preferences.uiScaleStep)
                            .labelsHidden()
                    }
                }
                .help("\u{2318}+ / \u{2318}\u{2212} anywhere, \u{2325}\u{2318}0 to reset")
                if preferences.uiScale != 1.0 {
                    Button("Reset to 100%") { preferences.resetUIScale() }
                        .glassButton()
                        .controlSize(.small)
                        .font(.caption)
                }
            }

            compactSection("Subject Colors", footer: "Each row has its own Reset button.") {
                if subjectCodes.isEmpty {
                    Text("Subjects appear here once your schedule loads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subjectCodes, id: \.self) { code in
                        SubjectColorRow(code: code, preferences: preferences, palette: palette)
                    }
                }
            }

            Button("Reset This Pane to Defaults") {
                preferences.theme = .auto
                preferences.fontChoice = .system
                preferences.uiScale = 1.0
            }
            .glassButton()
            .controlSize(.small)

            technicalSection([
                ("Accent", palette.accent.hex ?? "—"),
                ("Canvas top", palette.canvasTop.hex ?? "—"),
                ("Canvas bottom", palette.canvasBottom.hex ?? "—"),
                ("Font family", preferences.fontChoice.familyName ?? "system"),
                ("UI scale factor", String(format: "%.2f", preferences.uiScale)),
            ])
        }
    }

    // MARK: Schedule

    /// Calendar export, Google export, and program units — everything about
    /// the schedule the user set up once and rarely touches again.
    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            calendarSection
            googleSection

            compactSection(
                "Grades",
                footer: "Your program's total required units, for the completed-units progress on the Grades trend. SIS doesn't publish it."
            ) {
                compactRow("Program total units") {
                    HStack(spacing: 8) {
                        Text(preferences.programTotalUnits == 0 ? "Not set" : "\(preferences.programTotalUnits)")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $preferences.programTotalUnits, in: 0...400, step: 3).labelsHidden()
                    }
                }
            }

            Button("Reset This Pane to Defaults") {
                preferences.exportCalendarID = ""
                preferences.onlineExportCalendarID = ""
                preferences.googleClientID = ""
                preferences.googleCalendarID = ""
                preferences.termEndDate = Preferences.defaultTermEnd()
                preferences.programTotalUnits = 0
                preferences.visibleCalendarIDs = []
            }
            .glassButton()
            .controlSize(.small)

            technicalSection([
                ("Export calendar", preferences.exportCalendarID.isEmpty ? "none" : preferences.exportCalendarID),
                ("Online calendar", preferences.onlineExportCalendarID.isEmpty ? "none" : preferences.onlineExportCalendarID),
                ("Google calendar", preferences.googleCalendarID.isEmpty ? "none" : preferences.googleCalendarID),
                ("Cached sessions", "\(appState.portal.sessions.count)"),
                ("Last updated", appState.portal.lastUpdated.map { ISO8601DateFormatter().string(from: $0) } ?? "never"),
            ])
        }
    }

    // MARK: Notifications

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            notificationSection

            Button("Reset This Pane to Defaults") {
                preferences.notificationsEnabled = false
                preferences.notificationLeadMinutes = 15
            }
            .glassButton()
            .controlSize(.small)

            technicalSection([
                ("Authorization status", notifier.authorization.map { "\($0)" } ?? "unknown"),
                ("Lead time", "\(preferences.notificationLeadMinutes) minutes"),
                ("Start at login", LoginItem.isEnabled ? "enabled" : "disabled"),
            ])
        }
    }

    // MARK: Intelligence

    /// IntAssis, its models, the RAG tuning knobs, and the advanced
    /// generation/runtime knobs — everything AI-related in one place.
    private var intelligenceTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            aiSection
            downloadModelsSection
            advancedAITuningSection
            ragTuningSection
            technicalSection([
                ("llama-server binary", LlamaServerManager.locateBinary() ?? "not found"),
                ("Selected model path", ModelCatalog.entry(for: preferences.aiModel)
                    .map { ModelCatalog.localURL(for: $0).path } ?? "—"),
                ("Chat port", "8080"),
                ("Embed port", "8081"),
            ])
        }
    }

    /// Knobs the app already had fixed constants for — sampling temperature,
    /// the reply token budget, KV cache quantization, GPU offload — surfaced
    /// as real controls instead of staying hardcoded. Gated on `aiEnabled`
    /// like the rest of the pane; footers stay on screen, not behind a "?".
    private var advancedAITuningSection: some View {
        compactSection(
            "Advanced AI Tuning",
            footer: """
            Temperature: lower is more focused and repeatable, higher is more varied. \
            Output token budget: the ceiling on a single reply — raising it without \
            enough context headroom can make a turn refuse to run rather than truncate. \
            Quantizing the KV cache roughly halves its RAM cost per token of context; \
            turning it off approximates the older, more precise fp16 cache. GPU off \
            forces CPU-only, mainly useful for isolating a slowdown or crash. All four \
            restart the local model process when changed, and only affect the \
            llama-server-backed (Intel) chat model — the Apple Silicon MLX runtime \
            manages its own KV cache and always uses the GPU.
            """
        ) {
            if preferences.aiEnabled {
                compactRow("Response temperature") {
                    Text(String(format: "%.2f", preferences.aiTemperature)).foregroundStyle(.secondary)
                }
                Slider(value: $preferences.aiTemperature, in: 0...1, step: 0.05)
                compactRow("Output token budget") {
                    Text("\(preferences.aiOutputTokenBudget) tokens").foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(preferences.aiOutputTokenBudget) },
                        set: { preferences.aiOutputTokenBudget = Int($0) }
                    ),
                    in: Double(Preferences.aiOutputTokenBudgetRange.lowerBound)...Double(Preferences.aiOutputTokenBudgetRange.upperBound),
                    step: 128
                )
                compactRow("Quantize KV cache (q8_0)") {
                    Toggle("", isOn: $preferences.aiKVCacheQuantized).labelsHidden().toggleStyle(.switch)
                }
                compactRow("Use GPU (Metal)") {
                    Toggle("", isOn: $preferences.aiUseGPU).labelsHidden().toggleStyle(.switch)
                }
                Button("Reset to Defaults") {
                    preferences.aiTemperature = Preferences.aiDefaultTemperature
                    preferences.aiOutputTokenBudget = Preferences.aiDefaultOutputTokenBudget
                    preferences.aiKVCacheQuantized = true
                    preferences.aiUseGPU = true
                }
                .glassButton()
                .controlSize(.small)
                .font(.caption)
            } else {
                Text("Turn on IntAssis above to tune these.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Beta, off by default. Lives on the Intelligence pane alongside the
    /// local-model download steps and the RAG tuning knobs.
    private var aiSection: some View {
        compactSection(
            "AI (beta)",
            footer: """
            IntAssis: a floating assistant (bottom-left, when this is on) \
            that can read and add to your notes, read and add calendar \
            events, and read your grades — never delete, move, or change \
            one. Local is the default — pick a model below and everything \
            downloads and runs itself, no separate app needed, nothing \
            leaves this Mac.

            A cloud provider (OpenAI/Google/Anthropic) is opt-in: pick one \
            under Model source and paste in your own API key. That key and \
            your prompts go straight to the provider's own API — this \
            app's local model, and RAG note search, are untouched either way.

            It can be wrong, local or cloud. Treat anything it tells you \
            — a summary, a date, an answer from your notes — as a draft to \
            check, not a fact.
            """
        ) {
            compactRow("IntAssis") {
                Toggle("", isOn: $preferences.aiEnabled).labelsHidden().toggleStyle(.switch)
            }
            if preferences.aiEnabled {
                compactRow("Model source") {
                    Picker("", selection: $preferences.aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160, alignment: .trailing)
                }
                if preferences.aiProvider.needsAPIKey {
                    compactRow("Model") {
                        TextField("", text: $preferences.aiProviderModel, prompt: Text(preferences.aiProvider.defaultModel))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200, alignment: .trailing)
                    }
                    compactRow("API key") {
                        SecureField("", text: $apiKeyDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200, alignment: .trailing)
                            .onChange(of: apiKeyDraft) { _, newValue in
                                if newValue.isEmpty {
                                    AIProviderKeyStore.delete(for: preferences.aiProvider)
                                } else {
                                    try? AIProviderKeyStore.save(newValue, for: preferences.aiProvider)
                                }
                            }
                    }
                    Text("Stored in your Keychain, sent only to \(preferences.aiProvider.label)'s own API — never through this Mac's local model.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                compactRow("Permission") {
                    Picker("", selection: $preferences.aiPermission) {
                        ForEach(AssistantPermission.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                }
                Text(preferences.aiPermission.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                compactRow("Text reveal") {
                    Picker("", selection: $preferences.aiRevealAnimation) {
                        ForEach(AIRevealAnimation.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160, alignment: .trailing)
                }
                Button("Edit IntAssis instructions…") {
                    NSWorkspace.shared.open(AssistantInstructions.ensureExists())
                }
                .glassButton()
                .controlSize(.small)
                .font(.caption)
                compactRow("Thinking") {
                    Picker("", selection: $preferences.aiThinking) {
                        ForEach(AssistantThinking.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140, alignment: .trailing)
                }
                Text(preferences.aiThinking.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    compactRow("Context size") {
                        Text("\(preferences.aiContextSize) tokens").foregroundStyle(.secondary)
                    }
                    Button { showingContextInfo = true } label: {
                        Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("What does raising this do?")
                    .popover(isPresented: $showingContextInfo, arrowEdge: .bottom) { contextSizeInfoPopover }
                }
                Slider(
                    value: Binding(
                        get: { Double(preferences.aiContextSize) },
                        set: { preferences.aiContextSize = Int($0) }
                    ),
                    in: Double(Preferences.aiContextSizeRange.lowerBound)...Double(Preferences.aiContextSizeRange.upperBound),
                    step: 512
                )
                ramEstimateRow
                Text("How much conversation, notes, and tool results the model can hold at once. Restarts the local model process when changed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: preferences.aiEnabled) {
            if preferences.aiEnabled {
                refreshDownloaded()
            } else {
                // Not just "don't load more" — actually free what's running,
                // so turning the assistant off is also turning it off.
                LlamaServerManager.shared.stop()
            }
        }
        // Reloads whenever the provider switches (or the section first
        // appears) — the field must show *that* provider's own key, not
        // whichever one was on screen before, and must never leak one
        // provider's key into another's SecureField.
        .task(id: preferences.aiProvider) {
            apiKeyDraft = AIProviderKeyStore.load(for: preferences.aiProvider) ?? ""
        }
        .alert(item: $pendingModelLoad) { pending in
            Alert(
                title: Text("Switch to \(pending.entry.label)?"),
                message: Text(pending.message),
                primaryButton: .default(Text("Load Anyway")) { preferences.aiModel = pending.entry.id },
                secondaryButton: .cancel()
            )
        }
    }

    /// One `llama-server` binary, a short verified catalog of models
    /// (`ModelCatalog`) — pick one, it downloads with a real progress bar,
    /// and becomes the running model. The `-with-AI` dmg ships `llama-server`
    /// itself inside the bundle (`LlamaServerManager.binaryCandidates` finds
    /// it there first); the plain dmg still needs it once from Homebrew — the
    /// footer below only says so when neither is already present.
    private var downloadModelsSection: some View {
        compactSection(
            "Models",
            footer: LlamaServerManager.locateBinary() == nil
                ? "Needs llama-server itself installed once — brew install llama.cpp — that one step can't be done from inside the app. (The download-with-AI build ships it already and skips this.) Every model above downloads and runs itself after that."
                : "Every model above downloads and runs itself — nothing else to install."
        ) {
            ForEach(ModelCatalog.entries) { entry in
                modelRow(entry)
            }
            if let progress = installProgress {
                ProgressView(value: progress) {
                    Text(installingLabel ?? "Downloading…").font(.caption)
                }
            }
            if let error = installError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private func modelRow(_ entry: ModelCatalog.Entry) -> some View {
        let isSelected = preferences.aiModel == entry.id
        let isDownloaded = downloadedIDs.contains(entry.id)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label).font(.callout).fontWeight(isSelected ? .semibold : .regular)
                Text(entry.description).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else if isDownloaded {
                Button("Use this model") { considerSelecting(entry) }
                    .glassButton().controlSize(.small).font(.caption)
            } else {
                Button("Download") { Task { await installModel(entry) } }
                    .glassButton().controlSize(.small).font(.caption)
                    .disabled(installProgress != nil)
            }
        }
        .padding(.vertical, 4)
    }

    /// A model whose size crossed the memory-check threshold, held for
    /// confirmation before it's ever written to `preferences.aiModel`.
    private struct PendingModelLoad: Identifiable {
        let entry: ModelCatalog.Entry
        let availableBytes: UInt64
        var id: String { entry.id }

        var message: String {
            let modelGB = Double(entry.sizeBytes) / 1_073_741_824
            let availableGB = Double(availableBytes) / 1_073_741_824
            return String(format: "This model needs about %.1f GB. You have about %.1f GB available.", modelGB, availableGB)
        }
    }

    /// Never writes to `preferences.aiModel` directly, so a memory check can
    /// run *before* anything is committed — Cancel then needs no revert,
    /// since nothing changed yet.
    private func considerSelecting(_ entry: ModelCatalog.Entry) {
        guard entry.id != preferences.aiModel else { return }
        if let available = SystemMemory.availableBytes(),
           SystemMemory.shouldWarn(modelBytes: entry.sizeBytes, availableBytes: available) {
            pendingModelLoad = PendingModelLoad(entry: entry, availableBytes: available)
        } else {
            preferences.aiModel = entry.id
        }
    }

    /// Downloads `entry` (via the real memory-check gate above once it's on
    /// disk), plus the fixed embedding model alongside it if that isn't
    /// downloaded yet — one button covers both jobs, same promise the
    /// standalone-download requirement asked for.
    private func installModel(_ entry: ModelCatalog.Entry) async {
        installError = nil
        do {
            installingLabel = "Downloading \(entry.label)…"
            installProgress = 0
            for try await fraction in ModelCatalog.download(entry) {
                installProgress = fraction
            }
            if !ModelCatalog.isDownloaded(ModelCatalog.embedModel) {
                installingLabel = "Downloading \(ModelCatalog.embedModel.label)…"
                installProgress = 0
                for try await fraction in ModelCatalog.download(ModelCatalog.embedModel) {
                    installProgress = fraction
                }
            }
            refreshDownloaded()
            considerSelecting(entry)
        } catch {
            installError = "Couldn't download \(entry.label) — \(error.localizedDescription)"
        }
        installProgress = nil
        installingLabel = nil
    }

    private func refreshDownloaded() {
        downloadedIDs = Set(ModelCatalog.entries.filter(ModelCatalog.isDownloaded).map(\.id))
    }

    /// Live estimate of what `llama-server` will actually hold in RAM at the
    /// slider's current position — weights + KV cache + a flat compute-buffer
    /// overhead (`ModelCatalog.estimatedRAMBytes`). Turns red past the same
    /// 60%-of-available-RAM threshold `SystemMemory.shouldWarn` already gates
    /// the model-download confirmation with, so the two "is this too much
    /// RAM" checks in Settings agree with each other.
    private var ramEstimateRow: some View {
        let entry = ModelCatalog.entry(for: preferences.aiModel) ?? ModelCatalog.entries[0]
        let estimate = ModelCatalog.estimatedRAMBytes(
            for: entry, contextSize: preferences.aiContextSize, quantizedKVCache: preferences.aiKVCacheQuantized
        )
        let estimateGB = Double(estimate) / 1_073_741_824
        let tooMuch = SystemMemory.availableBytes().map {
            SystemMemory.shouldWarn(modelBytes: estimate, availableBytes: $0)
        } ?? false
        return HStack(spacing: 4) {
            Image(systemName: tooMuch ? "exclamationmark.triangle.fill" : "memorychip")
            Text(String(format: "~%.1f GB RAM at this context size", estimateGB))
        }
        .font(.caption2)
        .foregroundStyle(tooMuch ? .red : .secondary)
        .animation(Motion.drift(reduced: effectiveReduceMotion), value: tooMuch)
    }

    /// Same "?" popover language as `AssistantFloating`'s capabilities/thinking
    /// buttons — this app's one pattern for "explain the knob before you turn it."
    private var contextSizeInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context size").font(.headline)
            Text("""
            How many tokens (roughly ¾ of a word each) the model can hold at once — \
            your message, the conversation so far, any pinned note, and whatever it \
            retrieved for `/rag`, all combined. Qwen3-1.7B supports up to 32,768.
            """)
            VStack(alignment: .leading, spacing: 4) {
                Text("Higher").fontWeight(.semibold)
                Text("• Longer conversations before old messages get dropped")
                Text("• More room for pinned notes and RAG results, less truncation")
                Text("• Longer tool-call chains stay coherent")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Higher costs").fontWeight(.semibold)
                Text("• Far more RAM — the KV cache grows with context size, so 32k can need several GB more than 4k")
                Text("• Slower first reply — processing a long prompt takes longer before the model starts answering")
                Text("• Slower once the conversation is long — attention cost grows with how full the context is")
                Text("• On a Mac tight on RAM, llama-server can fail to start or get killed by the OS")
            }
            Text("Changing this restarts the local model process. Lower it back down if replies get sluggish or it stops starting.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding()
        .frame(width: 320)
    }

    /// How the assistant searches notes — chunk size, similarity floor,
    /// context budget, answer temperature.
    private var ragTuningSection: some View {
        compactSection(
            "AI Tuning",
            footer: """
            How the assistant searches your notes (the AI's own search, and /rag). Chunk size is how much \
            text is grouped per match; similarity floor is how loose a match counts as relevant — lower finds \
            more, at the risk of an unrelated note slipping in. Context budget caps how much matched text \
            reaches the answer model.
            """
        ) {
            compactRow("Chunk size") {
                Text("\(preferences.ragChunkSize) chars").foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.ragChunkSize) },
                    set: { preferences.ragChunkSize = Int($0) }
                ),
                in: 200...2000,
                step: 100
            )
            compactRow("Similarity floor") {
                Text(String(format: "%.2f", preferences.ragSimilarityFloor)).foregroundStyle(.secondary)
            }
            Slider(value: $preferences.ragSimilarityFloor, in: 0...1, step: 0.05)
            compactRow("Context budget") {
                Text("\(preferences.ragContextBudget) chars").foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.ragContextBudget) },
                    set: { preferences.ragContextBudget = Int($0) }
                ),
                in: 1000...20000,
                step: 500
            )
            compactRow("Answer temperature") {
                Text(String(format: "%.2f", preferences.ragAnswerTemperature)).foregroundStyle(.secondary)
            }
            Slider(value: $preferences.ragAnswerTemperature, in: 0...1, step: 0.05)
            Button("Reset to Defaults") {
                preferences.ragChunkSize = Preferences.ragDefaultChunkSize
                preferences.ragSimilarityFloor = Preferences.ragDefaultSimilarityFloor
                preferences.ragContextBudget = Preferences.ragDefaultContextBudget
                preferences.ragAnswerTemperature = Preferences.ragDefaultAnswerTemperature
            }
            .glassButton()
            .controlSize(.small)
            .font(.caption)
        }
    }

    // MARK: Data & Storage

    /// The 4 fixed (label, url) pairs `refreshDiskUsage()` and
    /// `dataStorageTab` both need — one source, not two hand-kept copies.
    private var dataStorageFiles: [(label: String, url: URL)] {
        [
            ("Schedule cache", ScheduleStore.fileURL),
            ("Notes & vault", NotesStore.defaultURL),
            ("Syllabus", SyllabusStore.defaultURL),
            ("Quiz decks", QuizStore.defaultRoot),
        ]
    }

    /// Every file this app writes to disk, with its real (cached) size and a
    /// way to get to it or clear it.
    private var dataStorageTab: some View {
        let downloadedModels = (ModelCatalog.entries + [ModelCatalog.embedModel]).filter(ModelCatalog.isDownloaded)
        let modelsTotal = downloadedModels.reduce(Int64(0)) { $0 + (modelSizes[$1.id] ?? 0) }
        let filesTotal = dataStorageFiles.reduce(Int64(0)) { $0 + (fileSizes[$1.label] ?? 0) }

        return VStack(alignment: .leading, spacing: 20) {
            compactSection(
                "Files",
                footer: "Everything this app stores — schedule, notes, syllabus, quiz decks. Reveal opens Finder with the file (or folder) selected; nothing here is deleted from this list."
            ) {
                compactRow("Total on disk") {
                    Text(byteCountFormatter.string(fromByteCount: filesTotal + modelsTotal))
                        .fontWeight(.semibold)
                }
                ForEach(dataStorageFiles, id: \.label) { file in
                    compactRow(file.label) {
                        HStack(spacing: 8) {
                            Text(byteCountFormatter.string(fromByteCount: fileSizes[file.label] ?? 0))
                                .foregroundStyle(.secondary)
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                            .glassButton().controlSize(.small).font(.caption)
                        }
                    }
                }
            }

            compactSection(
                "AI Models",
                footer: "Deleting the model currently selected in Intelligence is disabled — switch models first. Deleting frees disk space immediately; re-downloading is the only way back."
            ) {
                if downloadedModels.isEmpty {
                    Text("No models downloaded yet — see Intelligence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(downloadedModels) { entry in
                        compactRow(entry.label) {
                            HStack(spacing: 8) {
                                Text(byteCountFormatter.string(fromByteCount: modelSizes[entry.id] ?? 0))
                                    .foregroundStyle(.secondary)
                                Button("Delete", role: .destructive) {
                                    withAnimation(Motion.selection(reduced: effectiveReduceMotion)) {
                                        try? FileManager.default.removeItem(at: ModelCatalog.localURL(for: entry))
                                        refreshDownloaded()
                                    }
                                    refreshDiskUsage()
                                }
                                .buttonStyle(.borderless).controlSize(.small).font(.caption)
                                .disabled(entry.id == preferences.aiModel)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .task { refreshDiskUsage() }
    }

    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// A file's size, or a directory's recursive total — `NotesStore`'s
    /// vault and a downloaded `.mlx` model are both directories; a shallow
    /// `enumerator` sum treats either the same as a single file's
    /// `attributesOfItem`. Missing paths (nothing downloaded/written yet)
    /// read as zero rather than erroring. Pure — safe to call off the main
    /// actor from `refreshDiskUsage()`'s detached task.
    nonisolated private func fileSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let attributes = try? fm.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Computes every file/model size off the render path — the walk itself
    /// (`fileSize(at:)`) is unchanged, just moved to a detached background
    /// task instead of running synchronously in the view body on every
    /// SwiftUI re-evaluation. Called once when Data & Storage appears, and
    /// again right after a model delete.
    private func refreshDiskUsage() {
        let files = dataStorageFiles
        let models = (ModelCatalog.entries + [ModelCatalog.embedModel]).filter(ModelCatalog.isDownloaded)
        Task.detached(priority: .utility) { [self] in
            var newFileSizes: [String: Int64] = [:]
            for file in files { newFileSizes[file.label] = fileSize(at: file.url) }
            var newModelSizes: [String: Int64] = [:]
            for entry in models { newModelSizes[entry.id] = fileSize(at: ModelCatalog.localURL(for: entry)) }
            let finalFileSizes = newFileSizes
            let finalModelSizes = newModelSizes
            await MainActor.run {
                fileSizes = finalFileSizes
                modelSizes = finalModelSizes
            }
        }
    }

    // MARK: Account

    private var accountTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            compactSection("Account") {
                compactRow("Last updated") {
                    Text(appState.portal.lastUpdated.map {
                        $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "Never")
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Refresh Schedule") {
                        Task { await appState.portal.loadSchedule() }
                    }
                    Button("Edit Credentials") { appState.isEditing = true }
                    Spacer()
                    Button("Sign Out", role: .destructive) { appState.signOut() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            technicalSection([
                ("SIS endpoint", "sis1.pup.edu.ph"),
                ("Keychain service", "ph.edu.pup.sis8.portal"),
            ])
        }
    }

    // MARK: About

    /// Read through `UpdateCheck` so the version shown here and the version the
    /// update check compares against can't drift apart. Unknown when there's no
    /// Info.plist to read (a bare `swift run`) — better than a hardcoded
    /// stand-in, which silently goes stale at the next release.
    private var appVersion: String {
        UpdateCheck.currentVersion ?? "unknown"
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            compactSection("About") {
                compactRow("PUPSISPortal") {
                    HStack(spacing: 8) {
                        Text(updaterBridge.availableVersion.map { "v\(appVersion) — v\($0) available" } ?? "v\(appVersion)")
                            .foregroundStyle(.secondary)
                        Button("Check for Updates…") { appState.updaterController.checkForUpdates(nil) }
                            .glassButton().controlSize(.small).font(.caption)
                            .disabled(!appState.updaterController.updater.canCheckForUpdates)
                    }
                }
                compactRow("Check for updates automatically") {
                    Toggle("", isOn: Binding(
                        get: { appState.updaterController.updater.automaticallyChecksForUpdates },
                        set: { appState.updaterController.updater.automaticallyChecksForUpdates = $0 }
                    )).labelsHidden().toggleStyle(.switch)
                }
                compactRow("Author") { Text("Janvin D. Salvador").foregroundStyle(.secondary) }
                compactRow("Contact") {
                    Link("cgradying@gmail.com", destination: URL(string: "mailto:cgradying@gmail.com")!)
                        .font(.callout)
                }
                compactRow("LinkedIn") {
                    // ponytail: people-search link (safe) until the exact profile URL is known.
                    Link("Janvin D. Salvador",
                         destination: URL(string: "https://www.linkedin.com/search/results/people/?keywords=Janvin%20D.%20Salvador")!)
                        .font(.callout)
                }
            }

            compactSection("Support") {
                compactRow("Donate") { Text("Coming soon").foregroundStyle(.secondary) }
            }

            compactSection("Terms of Use") {
                Text("""
                PUPSISPortal is an unofficial, independent client for the PUP \
                Student Information System. It is not affiliated with, endorsed by, \
                or connected to the Polytechnic University of the Philippines.

                Use is limited to your own account and your own data, for personal, \
                non-commercial purposes — which is what PUP's Terms of Use permit. \
                The app never scrapes other students, bypasses authentication, or \
                redistributes SIS content.

                Your credentials stay in the macOS Keychain and your schedule, grades, \
                and notes stay on your Mac; nothing is sent anywhere but the PUP SIS \
                server and — only if you set it up — your own Google Calendar.

                The software is provided "as is", without warranty of any kind. You \
                are responsible for your use of it and for keeping to PUP's Terms of Use.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            technicalSection([
                ("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"),
                ("Bundle identifier", Bundle.main.bundleIdentifier ?? "unknown"),
                ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            ])
        }
    }
}

private extension SettingsView {
    @ViewBuilder
    var notificationSection: some View {
        compactSection(
            "Notifications",
            footer: """
            One reminder per class meeting, repeating weekly. Meetings you've \
            marked vacant are skipped. Reminders fire only while PUPSISPortal is \
            running — turn on Start at login (General) so it's always there to \
            fire them, even after a restart.
            """
        ) {
            compactRow("Remind me before class") {
                Toggle("", isOn: Binding(
                    // Not a plain binding: turning it on is what asks for
                    // authorization, and a toggle that stays on while nothing can
                    // fire is worse than one that refuses.
                    get: { preferences.notificationsEnabled },
                    set: { wants in
                        guard wants else {
                            preferences.notificationsEnabled = false
                            syncNotifications()
                            return
                        }
                        Task {
                            preferences.notificationsEnabled = await notifier.requestAuthorization()
                            syncNotifications()
                        }
                    }
                )).labelsHidden().toggleStyle(.switch)
            }

            compactRow("How early") {
                Picker("", selection: $preferences.notificationLeadMinutes) {
                    ForEach(Preferences.leadOptions, id: \.self) { minutes in
                        Text("\(minutes) minutes before").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 180, alignment: .trailing)
                .disabled(!preferences.notificationsEnabled)
                // Rebuilt from here, not only from the calendar: that view isn't
                // alive while this pane is on screen, so it can't do it for us.
                .onChange(of: preferences.notificationLeadMinutes) { syncNotifications() }
            }

            if notifier.authorization == .denied {
                compactRow("Notifications are turned off for this app") {
                    Button("Open System Settings…") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                        else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .glassButton().controlSize(.small).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var calendarSection: some View {
        compactSection("Calendar", footer: calendarFooter) {
            switch calendar.access {
            case .notDetermined:
                compactRow("Calendar.app") {
                    Button("Connect…") {
                        Task { await calendar.requestAccess() }
                    }
                    .glassButton().controlSize(.small).font(.caption)
                }

            case .denied:
                Label(
                    "Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

            case .granted:
                if calendar.calendars.isEmpty {
                    Text("No calendars found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.calendars) { info in
                        compactRow(info.title) {
                            HStack(spacing: 6) {
                                Circle().fill(info.color).frame(width: 8, height: 8)
                                Text(info.source).font(.caption2).foregroundStyle(.secondary)
                                Toggle("", isOn: Binding(
                                    get: { preferences.visibleCalendarIDs.contains(info.id) },
                                    set: { preferences.setCalendar(info.id, visible: $0) }
                                )).labelsHidden().toggleStyle(.switch)
                            }
                        }
                    }
                }

                if calendar.writableCalendars.isEmpty {
                    Text("None of your calendars can be edited, so classes can't be exported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    compactRow("In-person classes to") {
                        Picker("", selection: $preferences.exportCalendarID) {
                            Text("Choose a calendar…").tag("")
                            ForEach(calendar.writableCalendars) { info in
                                Text("\(info.title) · \(info.source)").tag(info.id)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .trailing)
                    }

                    // Route online classes to their own calendar — a separate
                    // "label" in Apple/Google Calendar — or leave them with the rest.
                    compactRow("Online classes to") {
                        Picker("", selection: $preferences.onlineExportCalendarID) {
                            Text("Same as in-person").tag("")
                            ForEach(calendar.writableCalendars) { info in
                                Text("\(info.title) · \(info.source)").tag(info.id)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .trailing)
                        .disabled(preferences.exportCalendarID.isEmpty)
                    }

                    compactRow("Repeat until") {
                        DatePicker("", selection: $preferences.termEndDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    compactRow("Your classes") {
                        Button("Add to Calendar…", action: exportClasses)
                            .glassButton().controlSize(.small).font(.caption)
                            .disabled(appState.portal.sessions.isEmpty
                                      || preferences.exportCalendarID.isEmpty)
                    }
                }
            }

            // Google (and any other) calendars flow into the app through
            // EventKit once the account is added to macOS — this is the way in.
            compactRow("Google & other accounts") {
                Button("Open Internet Accounts…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
                .glassButton().controlSize(.small).font(.caption)
            }

            // A plain file, so the schedule can go anywhere — Google Calendar's
            // web import, a phone — without granting calendar access at all.
            compactRow("Schedule file") {
                Button("Export .ics…", action: exportICS)
                    .glassButton().controlSize(.small).font(.caption)
                    .disabled(appState.portal.sessions.isEmpty)
            }

            if let result = exportResult {
                Text(result).font(.caption2).foregroundStyle(.secondary)
            }
            if let error = calendar.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    var calendarFooter: String {
        switch calendar.access {
        case .granted:
            """
            Ticked calendars appear alongside your classes in the week grid. \
            Adding your classes writes them as weekly repeats into the calendars you choose, \
            stopping on the date above; running it again replaces the ones this app added \
            and leaves your own events alone. Online classes can go to their own calendar — \
            pick one under "Online classes to" — otherwise they land with the rest, labelled \
            Online. Classes marked vacant for the term are left off; a class vacant for a single \
            week loses just that date. After the first export, status changes sync automatically. \
            Classes added this way stay hidden here so they don't show up twice — they're still \
            in Calendar.app and on your other devices. To use a Google calendar, add the account \
            in System Settings › Internet Accounts (with Calendars on) and it appears above.
            """
        default:
            "Nothing from your calendar is shown until you connect and pick which calendars to include. Google calendars appear here once the account is added in System Settings › Internet Accounts."
        }
    }

    @ViewBuilder
    var googleSection: some View {
        compactSection(
            "Google Calendar (direct)",
            footer: """
            Writes classes straight to Google, bypassing Apple Calendar (whose \
            Google sync is unreliable for repeating events). One-time setup: at \
            console.cloud.google.com create a project, enable the Google Calendar \
            API, add yourself as a Test user on the OAuth consent screen, then \
            create an OAuth client ID of type iOS with bundle ID \
            com.cgradying.pupsisportal and paste its Client ID above. While the \
            consent screen stays in testing, Google asks you to reconnect about \
            once a week.
            """
        ) {
            if !googleAuth.isConnected {
                compactRow("OAuth client ID") {
                    TextField("", text: $preferences.googleClientID)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: 220, alignment: .trailing)
                }
                compactRow("Google account") {
                    Button("Connect Google") { connectGoogle() }
                        .glassButton().controlSize(.small).font(.caption)
                        .disabled(preferences.googleClientID.trimmingCharacters(in: .whitespaces).isEmpty || googleBusy)
                }
            } else {
                compactRow("Export to") {
                    Picker("", selection: $preferences.googleCalendarID) {
                        Text("Choose a calendar…").tag("")
                        ForEach(googleCalendars) { cal in
                            Text(cal.summary).tag(cal.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .trailing)
                }
                compactRow("Your classes") {
                    Button("Export to Google", action: exportToGoogle)
                        .glassButton().controlSize(.small).font(.caption)
                        .disabled(appState.portal.sessions.isEmpty
                                  || preferences.googleCalendarID.isEmpty
                                  || googleBusy)
                }
                Button("Disconnect Google", role: .destructive) {
                    googleAuth.disconnect()
                    googleCalendars = []
                    googleResult = nil
                }
                .buttonStyle(.borderless).controlSize(.small).font(.caption)
            }

            if googleBusy {
                HStack { ProgressView().controlSize(.small); Text("Working…").font(.caption2).foregroundStyle(.secondary) }
            }
            if let googleResult {
                Text(googleResult).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    func connectGoogle() {
        googleBusy = true
        googleResult = nil
        Task {
            defer { googleBusy = false }
            do {
                try await googleAuth.connect()
                await loadGoogleCalendars()
            } catch {
                googleResult = error.localizedDescription
            }
        }
    }

    func loadGoogleCalendars() async {
        do {
            googleCalendars = try await appState.googleClient.listCalendars()
        } catch {
            googleResult = error.localizedDescription
        }
    }

    func exportToGoogle() {
        googleBusy = true
        googleResult = nil
        Task {
            defer { googleBusy = false }
            do {
                googleResult = try await appState.googleClient.exportClasses(
                    appState.portal.sessions,
                    weekStart: Weekday.weekStart(containing: .now),
                    until: preferences.termEndDate,
                    toCalendarID: preferences.googleCalendarID,
                    status: { preferences.termStatus(for: $0) }
                )
            } catch {
                googleResult = error.localizedDescription
            }
        }
    }

    func syncNotifications() {
        notifier.sync(appState.portal.sessions, preferences)
    }

    func exportICS() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PUPSIS-Schedule.ics"
        if let ics = UTType(filenameExtension: "ics") {
            panel.allowedContentTypes = [ics]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = ICSExporter.ics(
            for: appState.portal.sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            // Term status: an .ics VEVENT is a single repeating series, so it
            // carries whole-term status, not a single week's exception.
            status: { preferences.termStatus(for: $0) }
        )
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportResult = "Saved schedule to “\(url.lastPathComponent)”."
        } catch {
            exportResult = error.localizedDescription
        }
    }

    func exportClasses() {
        exportResult = calendar.exportClasses(
            appState.portal.sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            toCalendarID: preferences.exportCalendarID,
            onlineCalendarID: preferences.onlineExportCalendarID.isEmpty ? nil : preferences.onlineExportCalendarID,
            status: { preferences.status(for: $0, on: $1) },
            time: { preferences.time(for: $0, on: $1) }
        )
    }
}

/// The tab strip's "which page am I on" mark — a thin pixel-dither line
/// under the selected tab. Same `DitherFill`/`TimelineView` pairing
/// `HomeNoiseField.swift` already uses for its own ambient wave, scaled
/// down to a 3pt line instead of a full field: idles with a slow drift
/// rather than sitting static, pauses to one still frame under Reduce
/// Motion rather than merely slowing down.
private struct TabIndicatorLine: View {
    let color: Color
    let reduced: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduced ? nil : 0.16, paused: reduced)) { context in
            DitherFill(
                color: color,
                cell: 2,
                ramp: .wave(0.6),
                phase: reduced ? 0 : context.date.timeIntervalSinceReferenceDate * 0.5
            )
        }
        .frame(height: 3)
        .clipShape(Capsule())
    }
}

private struct SubjectColorRow: View {
    let code: String
    @ObservedObject var preferences: Preferences
    let palette: Palette

    @Environment(\.typography) private var typography

    var body: some View {
        HStack(spacing: 12) {
            // Binding rather than onChange: ColorPicker writes continuously
            // while the user drags, and the swatch has to follow.
            ColorPicker(
                selection: Binding(
                    get: { preferences.color(for: code, in: palette) },
                    set: { preferences.setColor($0, for: code) }
                ),
                supportsOpacity: false
            ) {
                Text(code)
                    .font(typography.blockCode)
            }

            Spacer()

            Button("Reset") { preferences.resetColor(for: code) }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(!preferences.hasCustomColor(for: code))
        }
        .padding(.vertical, 2)
    }
}
