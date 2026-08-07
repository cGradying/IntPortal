import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var credentials: Credentials?
    @Published var isEditing = false

    let portal = PortalController()
    let preferences = Preferences()
    let calendar = CalendarBridge()

    /// The current minute, republished on the minute boundary. The menu bar's
    /// "next class" has no view of its own to hang a `TimelineView` on, so the
    /// clock lives here where both the menu bar and any window can read it.
    @Published var now = Date()
    private var clock: Timer?

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

enum SidebarItem: String, CaseIterable, Identifiable {
    case schedule
    case today
    case grades
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .today: "Today"
        case .grades: "Grades"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: "calendar"
        case .today: "list.bullet.rectangle"
        case .grades: "graduationcap"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @State private var selection: SidebarItem = .schedule
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
            // No sidebar before sign-in: there is nowhere to navigate to yet.
            CredentialsView(existing: appState.credentials, onSave: appState.save)
        } else if let credentials = appState.credentials {
            NavigationSplitView {
                SidebarView(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            } detail: {
                switch selection {
                case .schedule:
                    CalendarView(
                        controller: appState.portal,
                        preferences: preferences,
                        calendar: appState.calendar,
                        credentials: credentials
                    )
                case .today:
                    AgendaView(appState: appState, preferences: preferences)
                case .grades:
                    GradesView(controller: appState.portal, preferences: preferences)
                case .settings:
                    SettingsView(
                        appState: appState,
                        preferences: preferences,
                        calendar: appState.calendar
                    )
                }
            }
            .frame(minWidth: 1040, minHeight: 600)
        }
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
