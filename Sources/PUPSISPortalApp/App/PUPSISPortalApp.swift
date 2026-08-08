import SwiftUI

@MainActor
final class AppState: ObservableObject {
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

    init() {
        credentials = KeychainStore.load()
        isEditing = credentials == nil
        startClock()
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

    var body: some View {
        content
            .environment(\.palette, preferences.theme.palette(for: systemScheme))
            // Keeps native controls (fields, pickers, popovers) in step with a
            // theme the user picked against their system setting.
            .preferredColorScheme(preferences.theme.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        if appState.isEditing || appState.credentials == nil {
            // No nav before sign-in: there is nowhere to go yet.
            CredentialsView(existing: appState.credentials, onSave: appState.save)
        } else if let credentials = appState.credentials {
            NavigationStack {
                destination(for: credentials)
                    // The pill lives in the title bar centre — a thin top switcher
                    // that clears the content, with the gear beside it. Each view
                    // keeps its own toolbar items alongside.
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            DestinationBar(selection: $appState.selection)
                        }
                        ToolbarItem(placement: .automatic) {
                            gearButton
                        }
                    }
            }
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
                credentials: credentials
            )
        case .today:
            AgendaView(appState: appState, preferences: preferences, calendar: appState.calendar, notes: appState.notes)
        case .grades:
            GradesView(controller: appState.portal, preferences: preferences)
        }
    }

    private var gearButton: some View {
        Button {
            appState.showingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Settings")
        .accessibilityLabel("Settings")
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
        .commands {
            // Settings by ⌘, in the app menu, now that it's a sheet not a row.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(appState.credentials == nil)
            }

            // Keep the destinations reachable from the keyboard without a sidebar.
            CommandGroup(after: .toolbar) {
                Button("Schedule") { appState.selection = .schedule }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Today") { appState.selection = .today }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Grades") { appState.selection = .grades }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
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
