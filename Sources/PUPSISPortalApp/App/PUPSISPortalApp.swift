import SwiftUI

/// The Schedule screen's controls, lifted out of `CalendarView` so the floating
/// nav island can drive them. Week nav / scale / show-cancelled are plain
/// state the island mutates directly; year-step and new-event are intents the
/// view consumes (they need `CalendarView`'s week/editor context).
@MainActor
final class ScheduleModel: ObservableObject {
    @Published var scale: CalendarScale = .week
    @Published var weekOffset = 0
    @Published var showCancelled = true
    /// Island → view: −1 / +1 to step by the current scale; the view resets it to 0.
    @Published var stepIntent = 0
    /// Island → view: bumped to request a new event at the default slot.
    @Published var newEventIntent = 0
}

@MainActor
final class AppState: ObservableObject {
    let schedule = ScheduleModel()
    @Published var credentials: Credentials?
    @Published var isEditing = false

    let portal = PortalController()
    let preferences = Preferences()
    let calendar = CalendarBridge()
    let notes = NotesStore()
    lazy var googleAuth = GoogleAuth { [preferences] in preferences.googleClientID }
    lazy var googleClient = GoogleCalendarClient(auth: googleAuth)

    /// The current minute, republished on the minute boundary. The menu bar's
    /// "next class" has no view of its own to hang a `TimelineView` on, so the
    /// clock lives here where both the menu bar and any window can read it.
    @Published var now = Date()
    private var clock: Timer?

    /// Which destination the window shows, and whether Settings is up. App-level
    /// so the menu commands (⌘1/2/3, ⌘,) can drive them, not just the view.
    @Published var selection: Destination = .schedule
    @Published var showingSettings = false

    /// The nav island's placement. Launch shows the island centred (a home
    /// launcher); opening a destination flies it to the top and reveals the
    /// screen. The island's home mark flips it back.
    @Published var isHome = true

    /// A newer release, once the launch check finds one. Stays nil otherwise —
    /// including when the check fails — so nothing appears unless there really
    /// is an update.
    @Published var availableUpdate: UpdateInfo?

    /// The note key the user is currently looking at, mirrored up from
    /// whichever screen has one open (today: `AgendaView`) — see the comment
    /// at its `.onChange`/`.onAppear` there. Read by the assistant to answer
    /// "summarize this note" without the model needing a key it was never told.
    @Published var openNoteKey: String?

    /// The floating assistant's own conversation state.
    let assistant = AssistantSession()

    /// The assistant's **own** `EventEditor`, separate from `CalendarView`'s.
    /// `EventEditor.undoManager` is only wired while `CalendarView` is on
    /// screen (`Views/CalendarView.swift`), so an edit made from the assistant
    /// while looking at Grades or Today would otherwise be un-undoable. Both
    /// editors share the same underlying `CalendarBridge`, so an assistant-made
    /// event still shows up once that bridge reloads.
    lazy var assistantEditor: EventEditor = {
        let editor = EventEditor(bridge: calendar)
        editor.onChange = { [weak self] in self?.reloadCalendarForAssistant() }
        return editor
    }()

    private func reloadCalendarForAssistant() {
        let thisWeek = Weekday.weekStart(containing: .now)
        let viewedWeek = Calendar.current.date(
            byAdding: .day, value: schedule.weekOffset * 7, to: thisWeek
        ) ?? thisWeek
        calendar.load(weekStart: viewedWeek, calendarIDs: preferences.visibleCalendarIDs)
    }

    /// Open a destination from the island or a menu command: select it and
    /// leave home so the island glides to the top.
    func open(_ destination: Destination) {
        selection = destination
        isHome = false
    }

    init() {
        credentials = KeychainStore.load()
        isEditing = credentials == nil
        isHome = preferences.islandStartHome
        startClock()
        checkForUpdate()
    }

    /// One anonymous GET at launch, detached so it never delays the first frame.
    /// Skipped entirely when the running version can't be read (`swift run`,
    /// tests) rather than guessed at — see `UpdateCheck.currentVersion`.
    private func checkForUpdate() {
        guard let current = UpdateCheck.currentVersion else { return }
        Task { [weak self] in
            let info = await UpdateCheck().check(current: current)
            guard let info else { return }
            await MainActor.run { self?.availableUpdate = info }
        }
    }

    /// Fires on each :00 rather than 60s after launch, so "in 25 min" flips when
    /// the wall clock does. `.common` keeps it ticking while a menu is open.
    private func startClock() {
        let fromNextMinute = NowLine.nextMinute.timeIntervalSinceNow
        clock = Timer.scheduledTimer(withTimeInterval: max(fromNextMinute, 1), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.now = Date() }
                }
                self?.clock.map { RunLoop.main.add($0, forMode: .common) }
            }
        }
        clock.map { RunLoop.main.add($0, forMode: .common) }
    }

    /// The next class right now, or `nil`. Vacant meetings are excluded by
    /// **this-week** status — the same per-week rule the day list and the grid
    /// use — so the menu bar never advertises a class the user cancelled this
    /// week. (Reminders stay term-wide in `Notifier`: a weekly-repeating trigger
    /// can't skip a single week.)
    var upcoming: NextClass.Upcoming? {
        NextClass.next(in: portal.sessions, at: now, isVacant: { session, date in
            preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
        })
    }

    /// Refresh from anywhere — the app menu, the menu bar — and reschedule
    /// reminders afterward. Routed through here (not the window) so a refresh
    /// with the window closed still keeps the OS's pending reminders in step.
    func refresh() async {
        await portal.loadSchedule()
        await portal.loadGrades()
        Notifier.shared.sync(portal.sessions, preferences)
    }

    func save(_ credentials: Credentials) {
        try? KeychainStore.save(credentials)
        self.credentials = credentials
        isEditing = false
        portal.status = .idle
    }

    func signOut() {
        KeychainStore.delete()
        // Both caches are this student's own data; signing out has to take them
        // off disk too, not just off screen.
        ScheduleStore.delete()
        GradesStore.delete()
        credentials = nil
        isEditing = true
        portal.status = .idle
        portal.sessions = []
        portal.lastUpdated = nil
        portal.refreshError = nil
        portal.grades = nil
        portal.gradesError = nil
        portal.gradeHistory = []
    }
}

/// The three main destinations. Settings is no longer one of these — it's a
/// sheet behind the gear button.
enum Destination: String, CaseIterable, Identifiable {
    case schedule
    case today
    case grades

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .today: "Today"
        case .grades: "Grades"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: "calendar"
        case .today: "list.bullet.rectangle"
        case .grades: "graduationcap"
        }
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        content
            .background(TrafficLights(autoHide: preferences.trafficLightsAutoHide))
            .environment(\.palette, preferences.theme.palette(for: systemScheme))
            // Keeps native controls (fields, pickers, popovers) in step with a
            // theme the user picked against their system setting.
            .preferredColorScheme(preferences.theme.colorScheme)
            // Same reasoning as CalendarView wiring its own EventEditor's
            // undoManager: SwiftUI only hands one out via the environment
            // inside a view, so the assistant's editor (a plain object on
            // AppState) has to be handed it explicitly, once, here.
            .onAppear { appState.assistantEditor.undoManager = undoManager }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isEditing || appState.credentials == nil {
            // No nav before sign-in: there is nowhere to go yet.
            CredentialsView(existing: appState.credentials, onSave: appState.save)
        } else if let credentials = appState.credentials {
            ZStack(alignment: .top) {
                // Base: a calm wash at home, the screen (inset below the floating
                // island) once open. Cross-fades under the gliding island.
                Group {
                    if appState.isHome {
                        preferences.theme.palette(for: systemScheme).canvasWash
                            .ignoresSafeArea()
                    } else {
                        destination(for: credentials)
                            .padding(.top, 40) // clear the slim top bar
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // A pixel-dither strip textures the otherwise-flat top bar.
                if !appState.isHome {
                    DitherBand(color: preferences.theme.palette(for: systemScheme).accent.opacity(0.6))
                        .frame(height: 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }

                // Invisible titlebar-style drag strip: moves the window in place of
                // background dragging (which fought the calendar's create-drag).
                // Below the island in z-order, so island buttons still win.
                WindowDragArea()
                    .frame(height: 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // The island itself never re-mounts — it *glides* from centre (home)
                // to the top (open), so opening reads as a move/expand, not a fade.
                // Hover morph keeps working because it's one live view throughout.
                NavIsland(appState: appState, schedule: appState.schedule, preferences: preferences)
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: appState.isHome ? .center : .top)
                    .padding(.top, appState.isHome ? 0 : 4)

                // Floating, reachable from every screen — only exists at all
                // once the beta toggle is on (Settings › Grades › AI (beta)).
                if preferences.aiEnabled {
                    AssistantFloating(appState: appState, preferences: preferences, session: appState.assistant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(16)
                }
            }
            // Fill the whole window — including the hidden title bar's strip — so
            // no grey window background shows there.
            .ignoresSafeArea()
            .background(preferences.theme.palette(for: systemScheme).canvasWash.ignoresSafeArea())
            .animation(Motion.island(reduced: reduceMotion), value: appState.isHome)
            .sheet(isPresented: $appState.showingSettings) { settingsSheet }
            .frame(minWidth: 900, minHeight: 600)
        }
    }

    @ViewBuilder
    private func destination(for credentials: Credentials) -> some View {
        switch appState.selection {
        case .schedule:
            CalendarView(
                controller: appState.portal,
                preferences: preferences,
                calendar: appState.calendar,
                credentials: credentials,
                schedule: appState.schedule,
                update: appState.availableUpdate
            )
        case .today:
            AgendaView(appState: appState, preferences: preferences, calendar: appState.calendar, notes: appState.notes)
        case .grades:
            GradesView(controller: appState.portal, preferences: preferences)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView(
                appState: appState,
                preferences: preferences,
                calendar: appState.calendar,
                googleAuth: appState.googleAuth
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { appState.showingSettings = false }
                }
            }
        }
        .frame(width: 560, height: 620)
    }
}

@main
struct PUPSISPortalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView(appState: appState, preferences: appState.preferences)
        }
        // The island is the only top chrome now — no native title bar competing.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Settings by ⌘, in the app menu, now that it's a sheet not a row.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(appState.credentials == nil)
            }

            // Keep the destinations reachable from the keyboard without a sidebar.
            CommandGroup(after: .toolbar) {
                Button("Schedule") { appState.open(.schedule) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Today") { appState.open(.today) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Grades") { appState.open(.grades) }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Home") { appState.isHome = true }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                // Schedule controls now live in the island; keep their shortcuts
                // global so they work whether or not the island is hovered.
                Button("Previous") { appState.schedule.stepIntent = -1 }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(appState.selection != .schedule)
                Button("Next") { appState.schedule.stepIntent = 1 }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(appState.selection != .schedule)
                Button("New Event") { appState.schedule.newEventIntent += 1 }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(appState.selection != .schedule)
            }

            CommandMenu("Account") {
                Button("Refresh") { Task { await appState.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(appState.credentials == nil)

                Divider()

                Button("Edit Credentials") { appState.isEditing = true }
                Button("Sign Out") { appState.signOut() }
                    .disabled(appState.credentials == nil)
            }
        }

        // The menu bar presence: what's next at a glance, and the reason the app
        // stays useful with its window closed — the OS keeps firing the reminders
        // it already holds, and this is how you still see the schedule and reopen.
        MenuBarExtra {
            MenuBarPanel(appState: appState, preferences: appState.preferences)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }

    static let mainWindowID = "main"
}
