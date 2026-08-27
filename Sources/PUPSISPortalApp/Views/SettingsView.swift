import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
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
    @State fileprivate var exportResult: String?
    @State fileprivate var googleCalendars: [GoogleCalendar] = []
    @State fileprivate var googleBusy = false
    @State fileprivate var googleResult: String?
    /// Mirrors the OS login-item status; re-read after every toggle so it can't
    /// drift from System Settings.
    @State fileprivate var launchAtLogin = LoginItem.isEnabled
    /// Gates the Misc tab's "Delete All Notes" confirmation dialog.
    @State private var confirmingWipe = false
    /// Whether the context-size explainer popover is showing.
    @State private var showingContextInfo = false

    /// Subjects the user can actually recolor: whatever is on screen right now.
    private var subjectCodes: [String] {
        ClassSession.subjectCodes(in: appState.portal.sessions)
    }

    var body: some View {
        TabView {
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
            calendarTab.tabItem { Label("Calendar", systemImage: "calendar") }
            notificationsTab.tabItem { Label("Notifications", systemImage: "bell.badge") }
            gradesTab.tabItem { Label("Grades", systemImage: "graduationcap") }
            accountTab.tabItem { Label("Account", systemImage: "person.crop.circle") }
            miscTab.tabItem { Label("Misc", systemImage: "ellipsis.circle") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(palette.accent)
        .background(palette.canvasWash.ignoresSafeArea())
        .navigationTitle("Settings")
        .task { await notifier.refreshAuthorization() }
        .task(id: googleAuth.isConnected) {
            if googleAuth.isConnected { await loadGoogleCalendars() }
        }
    }

    /// One grouped, wash-backed form per tab — the shared chrome lives here.
    @ViewBuilder
    private func settingsForm<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }

    /// Replaces `.pickerStyle(.inline)`, which rendered as a bare, unstyled
    /// system radio list — confirmed live as jarring the moment someone
    /// opens Settings to change the very thing this whole app is themed by.
    /// Same circle-with-selection-ring language `Blocks.swift`'s `SwatchRow`
    /// already uses for subject colors, adapted to a named room instead of
    /// a raw color.
    private var themeSwatchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(ThemeChoice.allCases) { choice in
                let selected = preferences.theme == choice
                Button {
                    preferences.theme = choice
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(choice.palette(for: systemScheme).accent)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle().strokeBorder(.primary, lineWidth: 2).opacity(selected ? 1 : 0)
                            }
                        Text(choice.label)
                            .font(.callout)
                            .foregroundStyle(selected ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appearanceTab: some View {
        settingsForm {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme").font(.callout)
                    themeSwatchGrid
                }
                Picker("Font", selection: $preferences.fontChoice) {
                    ForEach(FontChoice.allCases) { choice in
                        Text(choice.label)
                            .font(Typography(choice).screenTitle.weight(.regular))
                            .tag(choice)
                    }
                }
                Stepper(value: $preferences.uiScale, in: Preferences.uiScaleRange, step: Preferences.uiScaleStep) {
                    LabeledContent("UI Scale") {
                        Text("\(Int(preferences.uiScale * 100))%")
                    }
                }
                if preferences.uiScale != 1.0 {
                    Button("Reset to 100%") { preferences.resetUIScale() }
                }
                Text("Scales the whole app — \u{2318}+/\u{2318}\u{2212} also work from anywhere, \u{2325}\u{2318}0 to reset.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open on the home launcher", isOn: $preferences.islandStartHome)
                Toggle("Expand island on hover", isOn: $preferences.islandExpandOnHover)
                Toggle("Auto-hide window buttons", isOn: $preferences.trafficLightsAutoHide)
            } header: {
                Text("Dynamic Island")
            } footer: {
                Text("The floating island is the app's top bar. When it starts on the home launcher it sits centred and flies to the top when you open a screen. Expand-on-hover keeps it a compact pill until you point at it. Auto-hide keeps the red/yellow/green window buttons hidden until your cursor nears the top-left corner.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if subjectCodes.isEmpty {
                    Text("Subjects appear here once your schedule loads.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subjectCodes, id: \.self) { code in
                        SubjectColorRow(code: code, preferences: preferences, palette: palette)
                    }
                }
            } header: {
                Text("Subject Colors")
            } footer: {
                Text("Colors are remembered per subject code and survive a refresh.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calendarTab: some View {
        settingsForm {
            calendarSection
            googleSection
        }
    }

    private var notificationsTab: some View {
        settingsForm { notificationSection }
    }

    private var gradesTab: some View {
        settingsForm {
            Section {
                Stepper(value: $preferences.programTotalUnits, in: 0...400, step: 3) {
                    LabeledContent("Program total units") {
                        Text(preferences.programTotalUnits == 0
                             ? "Not set"
                             : "\(preferences.programTotalUnits)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Grades")
            } footer: {
                Text("Your program's total required units, for the completed-units progress on the Grades trend. SIS doesn't publish it.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Beta, off by default. Lives on the Misc tab alongside the local-model
    /// download steps and the RAG tuning knobs — everything AI-related in
    /// one place, rather than a toggle stranded on the Grades tab.
    private var aiSection: some View {
        Section {
            Toggle("IntAssis", isOn: $preferences.aiEnabled)
            if preferences.aiEnabled {
                Picker("Permission", selection: $preferences.aiPermission) {
                    ForEach(AssistantPermission.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                Text(preferences.aiPermission.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Text reveal", selection: $preferences.aiRevealAnimation) {
                    ForEach(AIRevealAnimation.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text("How Replace/Insert below animates in — a connected sweep down each line, or each word fading in on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Edit IntAssis instructions…") {
                    NSWorkspace.shared.open(AssistantInstructions.ensureExists())
                }
                .font(.caption)
                Picker("Thinking", selection: $preferences.aiThinking) {
                    ForEach(AssistantThinking.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                Text(preferences.aiThinking.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        LabeledContent("Context size", value: "\(preferences.aiContextSize) tokens")
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
                }
                Text("How much conversation, notes, and tool results the model can hold at once. Restarts the local model process when changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("AI (beta)")
        } footer: {
            Text("""
            IntAssis: a floating assistant (bottom-left, when this is on) \
            that can read and add to your notes, read and add calendar \
            events, and read your grades — never delete, move, or change \
            one. Pick a model below — everything downloads and runs itself, \
            no separate app needed.

            Everything it sees and does stays on this Mac, talking only to a \
            `llama-server` process this app starts and stops on its own. \
            There is no cloud provider and no way to point this at one.

            **It runs locally and can be wrong.** Treat anything it tells you \
            — a summary, a date, an answer from your notes — as a draft to \
            check, not a fact.
            """)
            .foregroundStyle(.secondary)
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
    /// and becomes the running model. The one real remaining dependency is
    /// `llama-server` itself (`brew install llama.cpp`, once); model weights
    /// are entirely in-app after that.
    private var downloadModelsSection: some View {
        Section {
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
        } header: {
            Text("Models")
        } footer: {
            Text("Needs `llama-server` itself installed once — `brew install llama.cpp` — that one step can't be done from inside the app. Every model above downloads and runs itself after that.")
                .foregroundStyle(.secondary)
        }
    }

    private func modelRow(_ entry: ModelCatalog.Entry) -> some View {
        let isSelected = preferences.aiModel == entry.id
        let isDownloaded = downloadedIDs.contains(entry.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label).font(.callout).fontWeight(isSelected ? .semibold : .regular)
                    Text(entry.description).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else if isDownloaded {
                    Button("Use this model") { considerSelecting(entry) }.font(.caption)
                } else {
                    Button("Download") { Task { await installModel(entry) } }
                        .font(.caption).disabled(installProgress != nil)
                }
            }
        }
        .padding(.vertical, 2)
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
            for try await fraction in LlamaCppClient.download(from: entry.url, to: ModelCatalog.localURL(for: entry)) {
                installProgress = fraction
            }
            if !ModelCatalog.isDownloaded(ModelCatalog.embedModel) {
                installingLabel = "Downloading \(ModelCatalog.embedModel.label)…"
                installProgress = 0
                for try await fraction in LlamaCppClient.download(
                    from: ModelCatalog.embedModel.url, to: ModelCatalog.localURL(for: ModelCatalog.embedModel)
                ) {
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
        let estimate = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: preferences.aiContextSize)
        let estimateGB = Double(estimate) / 1_073_741_824
        let tooMuch = SystemMemory.availableBytes().map {
            SystemMemory.shouldWarn(modelBytes: estimate, availableBytes: $0)
        } ?? false
        return HStack(spacing: 4) {
            Image(systemName: tooMuch ? "exclamationmark.triangle.fill" : "memorychip")
            Text(String(format: "~%.1f GB RAM at this context size", estimateGB))
        }
        .font(.caption)
        .foregroundStyle(tooMuch ? .red : .secondary)
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

    private var miscTab: some View {
        settingsForm {
            Section {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([NotesStore.defaultURL])
                }
            } header: {
                Text("Notes Database")
            } footer: {
                Text("Opens Finder with notes.json selected — the file everything in Notes is stored in.")
                    .foregroundStyle(.secondary)
            }

            aiSection
            downloadModelsSection

            Section {
                Button("Delete All Notes…", role: .destructive) { confirmingWipe = true }
            } header: {
                Text("Wipe Notes")
            } footer: {
                Text("Deletes every note, folder, and pasted image. Login, schedule/grades cache, and settings are untouched.")
                    .foregroundStyle(.secondary)
            }
            .confirmationDialog(
                "Delete all notes?",
                isPresented: $confirmingWipe
            ) {
                Button("Delete Everything", role: .destructive) { appState.notes.wipeAll() }
            } message: {
                Text("This deletes every note, folder, and pasted image. This cannot be undone.")
            }

            Section {
                VStack(alignment: .leading) {
                    LabeledContent("Chunk size", value: "\(preferences.ragChunkSize) chars")
                    Slider(
                        value: Binding(
                            get: { Double(preferences.ragChunkSize) },
                            set: { preferences.ragChunkSize = Int($0) }
                        ),
                        in: 200...2000,
                        step: 100
                    )
                }
                VStack(alignment: .leading) {
                    LabeledContent("Similarity floor", value: String(format: "%.2f", preferences.ragSimilarityFloor))
                    Slider(value: $preferences.ragSimilarityFloor, in: 0...1, step: 0.05)
                }
                VStack(alignment: .leading) {
                    LabeledContent("Context budget", value: "\(preferences.ragContextBudget) chars")
                    Slider(
                        value: Binding(
                            get: { Double(preferences.ragContextBudget) },
                            set: { preferences.ragContextBudget = Int($0) }
                        ),
                        in: 1000...20000,
                        step: 500
                    )
                }
                VStack(alignment: .leading) {
                    LabeledContent("Answer temperature", value: String(format: "%.2f", preferences.ragAnswerTemperature))
                    Slider(value: $preferences.ragAnswerTemperature, in: 0...1, step: 0.05)
                }
                Button("Reset to Defaults") {
                    preferences.ragChunkSize = Preferences.ragDefaultChunkSize
                    preferences.ragSimilarityFloor = Preferences.ragDefaultSimilarityFloor
                    preferences.ragContextBudget = Preferences.ragDefaultContextBudget
                    preferences.ragAnswerTemperature = Preferences.ragDefaultAnswerTemperature
                }
                .font(.caption)
            } header: {
                Text("AI Tuning")
            } footer: {
                Text("""
                How the assistant searches your notes (the AI's own search, and `/rag`). Chunk size is how much \
                text is grouped per match; similarity floor is how loose a match counts as relevant — lower finds \
                more, at the risk of an unrelated note slipping in. Context budget caps how much matched text \
                reaches the answer model.
                """)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var accountTab: some View {
        settingsForm {
            Section("Account") {
                LabeledContent("Last updated") {
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
            }
        }
    }

    /// Read through `UpdateCheck` so the version shown here and the version the
    /// update check compares against can't drift apart. Unknown when there's no
    /// Info.plist to read (a bare `swift run`) — better than a hardcoded
    /// stand-in, which silently goes stale at the next release.
    private var appVersion: String {
        UpdateCheck.currentVersion ?? "unknown"
    }

    private var aboutTab: some View {
        settingsForm {
            Section("About") {
                LabeledContent("PUPSISPortal") {
                    HStack {
                        Text(updaterBridge.availableVersion.map { "v\(appVersion) — v\($0) available" } ?? "v\(appVersion)")
                        Button("Check for Updates…") { appState.updaterController.checkForUpdates(nil) }
                            .disabled(!appState.updaterController.updater.canCheckForUpdates)
                    }
                }
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { appState.updaterController.updater.automaticallyChecksForUpdates },
                    set: { appState.updaterController.updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent("Author", value: "Janvin D. Salvador")
                LabeledContent("Contact") {
                    Link("cgradying@gmail.com", destination: URL(string: "mailto:cgradying@gmail.com")!)
                }
                LabeledContent("LinkedIn") {
                    // ponytail: people-search link (safe) until the exact profile URL is known.
                    Link("Janvin D. Salvador",
                         destination: URL(string: "https://www.linkedin.com/search/results/people/?keywords=Janvin%20D.%20Salvador")!)
                }
            }

            Section("Support") {
                LabeledContent("Donate") {
                    Text("Coming soon").foregroundStyle(.secondary)
                }
            }

            Section {
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
            } header: {
                Text("Terms of Use")
            }
        }
    }
}

private extension SettingsView {
    @ViewBuilder
    var notificationSection: some View {
        Section {
            Toggle("Remind me before class", isOn: Binding(
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
            ))

            Picker("How early", selection: $preferences.notificationLeadMinutes) {
                ForEach(Preferences.leadOptions, id: \.self) { minutes in
                    Text("\(minutes) minutes before").tag(minutes)
                }
            }
            .disabled(!preferences.notificationsEnabled)
            // Rebuilt from here, not only from the calendar: that view isn't
            // alive while this pane is on screen, so it can't do it for us.
            .onChange(of: preferences.notificationLeadMinutes) { syncNotifications() }

            if notifier.authorization == .denied {
                LabeledContent("Notifications are turned off for this app") {
                    Button("Open System Settings…") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                        else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, wants in
                    LoginItem.setEnabled(wants)
                    // Reflect what actually took effect, in case registration failed.
                    launchAtLogin = LoginItem.isEnabled
                }
        } header: {
            Text("Notifications")
        } footer: {
            Text("""
            One reminder per class meeting, repeating weekly. Meetings you've \
            marked vacant are skipped. Reminders fire only while PUPSISPortal is \
            running — turn on Start at login so it's always there to fire them, \
            even after a restart.
            """)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var calendarSection: some View {
        Section {
            switch calendar.access {
            case .notDetermined:
                LabeledContent("Calendar.app") {
                    Button("Connect…") {
                        Task { await calendar.requestAccess() }
                    }
                }

            case .denied:
                Label(
                    "Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)

            case .granted:
                if calendar.calendars.isEmpty {
                    Text("No calendars found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.calendars) { info in
                        Toggle(isOn: Binding(
                            get: { preferences.visibleCalendarIDs.contains(info.id) },
                            set: { preferences.setCalendar(info.id, visible: $0) }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(info.title)
                                    // The account, so a Google calendar is
                                    // identifiable next to an iCloud one.
                                    Text(info.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Circle().fill(info.color).frame(width: 10, height: 10)
                            }
                        }
                    }
                }

                if calendar.writableCalendars.isEmpty {
                    Text("None of your calendars can be edited, so classes can't be exported.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("In-person classes to", selection: $preferences.exportCalendarID) {
                        Text("Choose a calendar…").tag("")
                        ForEach(calendar.writableCalendars) { info in
                            Text("\(info.title) · \(info.source)").tag(info.id)
                        }
                    }

                    // Route online classes to their own calendar — a separate
                    // "label" in Apple/Google Calendar — or leave them with the rest.
                    Picker("Online classes to", selection: $preferences.onlineExportCalendarID) {
                        Text("Same as in-person").tag("")
                        ForEach(calendar.writableCalendars) { info in
                            Text("\(info.title) · \(info.source)").tag(info.id)
                        }
                    }
                    .disabled(preferences.exportCalendarID.isEmpty)

                    DatePicker(
                        "Repeat until",
                        selection: $preferences.termEndDate,
                        displayedComponents: .date
                    )

                    LabeledContent("Your classes") {
                        Button("Add to Calendar…", action: exportClasses)
                            .disabled(appState.portal.sessions.isEmpty
                                      || preferences.exportCalendarID.isEmpty)
                    }
                }
            }

            // Google (and any other) calendars flow into the app through
            // EventKit once the account is added to macOS — this is the way in.
            LabeledContent("Google & other accounts") {
                Button("Open Internet Accounts…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
            }

            // A plain file, so the schedule can go anywhere — Google Calendar's
            // web import, a phone — without granting calendar access at all.
            LabeledContent("Schedule file") {
                Button("Export .ics…", action: exportICS)
                    .disabled(appState.portal.sessions.isEmpty)
            }

            if let result = exportResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = calendar.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text(calendarFooter)
                .foregroundStyle(.secondary)
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
        Section {
            if !googleAuth.isConnected {
                TextField("OAuth client ID", text: $preferences.googleClientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Google account") {
                    Button("Connect Google") { connectGoogle() }
                        .disabled(preferences.googleClientID.trimmingCharacters(in: .whitespaces).isEmpty || googleBusy)
                }
            } else {
                Picker("Export to", selection: $preferences.googleCalendarID) {
                    Text("Choose a calendar…").tag("")
                    ForEach(googleCalendars) { cal in
                        Text(cal.summary).tag(cal.id)
                    }
                }

                LabeledContent("Your classes") {
                    Button("Export to Google", action: exportToGoogle)
                        .disabled(appState.portal.sessions.isEmpty
                                  || preferences.googleCalendarID.isEmpty
                                  || googleBusy)
                }

                Button("Disconnect Google", role: .destructive) {
                    googleAuth.disconnect()
                    googleCalendars = []
                    googleResult = nil
                }
            }

            if googleBusy {
                HStack { ProgressView().controlSize(.small); Text("Working…").foregroundStyle(.secondary) }
            }
            if let googleResult {
                Text(googleResult).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Google Calendar (direct)")
        } footer: {
            Text("""
            Writes classes straight to Google, bypassing Apple Calendar (whose \
            Google sync is unreliable for repeating events). One-time setup: at \
            console.cloud.google.com create a project, enable the Google Calendar \
            API, add yourself as a Test user on the OAuth consent screen, then \
            create an OAuth client ID of type iOS with bundle ID \
            com.cgradying.pupsisportal and paste its Client ID above. While the \
            consent screen stays in testing, Google asks you to reconnect about \
            once a week.
            """)
            .foregroundStyle(.secondary)
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
                .disabled(!preferences.hasCustomColor(for: code))
        }
    }
}
