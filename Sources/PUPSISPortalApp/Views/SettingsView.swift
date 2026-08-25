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
    /// Ollama models present on this machine, refreshed when the AI section shows.
    @State private var installedModels: [String] = []
    /// Each installed model's on-disk weight size, for the memory check before
    /// switching to one. Keyed by name rather than reusing `installedModels`'
    /// shape, so that already-shipped, already-tested property stays untouched.
    @State private var modelSizes: [String: Int64] = [:]
    /// Held here rather than acted on immediately when a pick would need more
    /// memory than looks available — `.alert(item:)` below asks first.
    @State private var pendingModelLoad: PendingModelLoad?
    /// Ollama models currently loaded in memory that aren't the selected one.
    @State private var runningOthers: [String] = []
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @State fileprivate var exportResult: String?
    @State fileprivate var googleCalendars: [GoogleCalendar] = []
    @State fileprivate var googleBusy = false
    @State fileprivate var googleResult: String?
    /// Mirrors the OS login-item status; re-read after every toggle so it can't
    /// drift from System Settings.
    @State fileprivate var launchAtLogin = LoginItem.isEnabled
    /// Gates the Misc tab's "Delete All Notes" confirmation dialog.
    @State private var confirmingWipe = false

    /// Subjects the user can actually recolor: whatever is on screen right now.
    private var subjectCodes: [String] {
        Array(Set(appState.portal.sessions.map(\.subjectCode))).sorted()
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

    private var appearanceTab: some View {
        settingsForm {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.theme) {
                    ForEach(ThemeChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.inline)
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
            Toggle("Floating assistant", isOn: $preferences.aiEnabled)
            if preferences.aiEnabled {
                if installedModels.isEmpty {
                    LabeledContent("Model") {
                        Text("No models found — is Ollama running?")
                            .foregroundStyle(.secondary)
                    }
                    Button("Check again") { Task { await loadModels() } }
                } else {
                    Picker("Model", selection: modelSelectionBinding) {
                        ForEach(installedModels, id: \.self) { Text($0).tag($0) }
                    }
                    if runningOthers.isEmpty == false {
                        Button("Unload other running models (\(runningOthers.count))") {
                            Task { await unloadOthers() }
                        }
                        .font(.caption)
                    }
                }
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
                Button("Edit assistant instructions…") {
                    NSWorkspace.shared.open(AssistantInstructions.ensureExists())
                }
                .font(.caption)
            }
        } header: {
            Text("AI (beta)")
        } footer: {
            Text("""
            A floating assistant (bottom-left, when this is on) that can read \
            and add to your notes, read and add calendar events, and read your \
            grades — never delete, move, or change one. Needs \
            [Ollama](https://ollama.com) running on this Mac (`ollama serve`) \
            with a model pulled — nothing else is installed for you.

            Everything it sees and does stays on this Mac, talking only to that \
            local server. There is no cloud provider and no way to point this \
            at one.
            """)
            .foregroundStyle(.secondary)
        }
        .task(id: preferences.aiEnabled) {
            if preferences.aiEnabled {
                await loadModels()
                await refreshRunningOthers()
            } else {
                // Not just "don't load more" — actually free what's running,
                // so turning the assistant off is also turning it off.
                LlamaServerManager.shared.stop()
            }
        }
        .task(id: preferences.aiModel) {
            guard preferences.aiEnabled else { return }
            // A moment for the onChange-triggered unload above to land before
            // asking Ollama what's still resident.
            try? await Task.sleep(for: .seconds(1))
            await refreshRunningOthers()
        }
        .alert(item: $pendingModelLoad) { pending in
            Alert(
                title: Text("Load \(pending.name)?"),
                message: Text(pending.message),
                primaryButton: .default(Text("Load Anyway")) { commitModel(pending.name) },
                secondaryButton: .cancel()
            )
        }
    }

    /// Copy-pasteable terminal steps for the two things `aiSection` needs
    /// installed — Ollama isn't bundled, and neither the chat model nor the
    /// embedding model are picked for the user. `qwen2.5-coder:1.5b` is
    /// called out as the small/fast default; the caveat about tool-calling
    /// is real (confirmed live) rather than theoretical, so it's worth the
    /// line rather than a silent surprise the first time `/rag` behaves
    /// differently from a plain question.
    private var downloadModelsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                modelStep(1, "Install Ollama", "brew install ollama")
                modelStep(2, "Start it", "ollama serve")
                modelStep(3, "Pull a chat model", "ollama pull qwen2.5-coder:1.5b")
                Text("Small and fast, the default this app is built against. A model this size sometimes answers directly instead of actually searching your notes — `/rag \"question\"` always searches, regardless of model.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                modelStep(4, "Pull the embedding model", "ollama pull nomic-embed-text")
                Text("Powers note search (`ragEmbedModel` below) — a plain chat model can't embed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                modelStep(5, "Optional: grounded /rag answers", "brew install llama.cpp")
                Text("The model downloads itself on first use — nothing to pull by hand.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Download Models")
        } footer: {
            Text("Run these in Terminal, then hit “Check again” above (or just reopen this tab).")
                .foregroundStyle(.secondary)
        }
    }

    private func modelStep(_ number: Int, _ label: String, _ command: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption)
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// A model whose size crossed the memory-check threshold, held for
    /// confirmation before it's ever written to `preferences.aiModel`.
    private struct PendingModelLoad: Identifiable {
        let name: String
        let modelBytes: Int64
        let availableBytes: UInt64
        var id: String { name }

        var message: String {
            let modelGB = Double(modelBytes) / 1_073_741_824
            let availableGB = Double(availableBytes) / 1_073_741_824
            return String(format: "This model needs about %.1f GB. You have about %.1f GB available.", modelGB, availableGB)
        }
    }

    /// The Picker's binding: never writes to `preferences.aiModel` directly,
    /// so a check can run *before* anything is committed — Cancel then needs
    /// no revert, since nothing changed yet.
    private var modelSelectionBinding: Binding<String> {
        Binding(get: { preferences.aiModel }, set: considerSelecting)
    }

    private func considerSelecting(_ name: String) {
        guard name != preferences.aiModel else { return }
        if let bytes = modelSizes[name], let available = SystemMemory.availableBytes(),
           SystemMemory.shouldWarn(modelBytes: bytes, availableBytes: available) {
            pendingModelLoad = PendingModelLoad(name: name, modelBytes: bytes, availableBytes: available)
        } else {
            commitModel(name)
        }
    }

    /// Switching here doesn't unload what was running before — Ollama keeps
    /// it resident until its own idle timeout, so two models can end up
    /// competing for the machine. Free the old one the moment a different
    /// one is picked.
    private func commitModel(_ name: String) {
        let old = preferences.aiModel
        preferences.aiModel = name
        guard old != name, !old.isEmpty else { return }
        Task { await OllamaClient().unload(model: old) }
    }

    private func loadModels() async {
        let details = await OllamaClient.installedModelsDetailed()
        installedModels = details.map(\.name).sorted()
        modelSizes = Dictionary(uniqueKeysWithValues: details.map { ($0.name, $0.size) })
        // Pick something usable rather than leaving the picker on a stale or
        // empty name the user never chose — routed through the same check,
        // so a large default doesn't skip the confirmation either.
        if !installedModels.contains(preferences.aiModel), let first = installedModels.first {
            considerSelecting(first)
        }
    }

    /// Loaded models other than the one currently selected — what the manual
    /// "Unload other running models" button offers to clean up. Covers models
    /// left resident from outside the app (`ollama run <x>` in a terminal).
    private func refreshRunningOthers() async {
        let running = await OllamaClient.runningModels()
        runningOthers = running.filter { $0 != preferences.aiModel }
    }

    private func unloadOthers() async {
        let client = OllamaClient()
        for model in runningOthers {
            await client.unload(model: model)
        }
        await refreshRunningOthers()
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
                Stepper(value: $preferences.ragChunkSize, in: 200...2000, step: 100) {
                    LabeledContent("Chunk size", value: "\(preferences.ragChunkSize) chars")
                }
                VStack(alignment: .leading) {
                    LabeledContent("Similarity floor", value: String(format: "%.2f", preferences.ragSimilarityFloor))
                    Slider(value: $preferences.ragSimilarityFloor, in: 0...1, step: 0.05)
                }
                Stepper(value: $preferences.ragContextBudget, in: 1000...20000, step: 500) {
                    LabeledContent("Context budget", value: "\(preferences.ragContextBudget) chars")
                }
                VStack(alignment: .leading) {
                    LabeledContent("Answer temperature", value: String(format: "%.2f", preferences.ragAnswerTemperature))
                    Slider(value: $preferences.ragAnswerTemperature, in: 0...1, step: 0.05)
                }
                TextField("Embed model", text: $preferences.ragEmbedModel)
                Button("Reset to Defaults") {
                    preferences.ragChunkSize = Preferences.ragDefaultChunkSize
                    preferences.ragSimilarityFloor = Preferences.ragDefaultSimilarityFloor
                    preferences.ragContextBudget = Preferences.ragDefaultContextBudget
                    preferences.ragAnswerTemperature = Preferences.ragDefaultAnswerTemperature
                    preferences.ragEmbedModel = Preferences.ragDefaultEmbedModel
                }
                .font(.caption)
            } header: {
                Text("AI Tuning")
            } footer: {
                Text("""
                How the assistant searches your notes (the AI's own search, and `/rag`). Chunk size is how much \
                text is grouped per match; similarity floor is how loose a match counts as relevant — lower finds \
                more, at the risk of an unrelated note slipping in. Context budget caps how much matched text \
                reaches the answer model. Embed model must actually support embeddings — a plain chat model 404s.
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
