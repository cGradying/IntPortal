import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var credentials: Credentials?
    @Published var isEditing = false

    let portal = PortalController()
    let preferences = Preferences()

    init() {
        credentials = KeychainStore.load()
        isEditing = credentials == nil
    }

    func save(_ credentials: Credentials) {
        try? KeychainStore.save(credentials)
        self.credentials = credentials
        isEditing = false
        portal.status = .idle
    }

    func signOut() {
        KeychainStore.delete()
        // The cache is this student's own class schedule; signing out has to
        // take it off disk too, not just off screen.
        ScheduleStore.delete()
        credentials = nil
        isEditing = true
        portal.status = .idle
        portal.sessions = []
        portal.lastUpdated = nil
        portal.refreshError = nil
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case schedule
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: "calendar"
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
                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            } detail: {
                switch selection {
                case .schedule:
                    CalendarView(
                        controller: appState.portal,
                        preferences: preferences,
                        credentials: credentials
                    )
                case .settings:
                    SettingsView(appState: appState, preferences: preferences)
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
        WindowGroup {
            ContentView(appState: appState, preferences: appState.preferences)
        }
        .commands {
            CommandMenu("Account") {
                Button("Refresh Schedule") {
                    Task { await appState.portal.loadSchedule() }
                }
                .keyboardShortcut("r")
                .disabled(appState.credentials == nil)

                Divider()

                Button("Edit Credentials") { appState.isEditing = true }
                Button("Sign Out") { appState.signOut() }
                    .disabled(appState.credentials == nil)
            }
        }
    }
}
