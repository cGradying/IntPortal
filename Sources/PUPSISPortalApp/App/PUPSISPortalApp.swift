import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var credentials: Credentials?
    @Published var isEditing = false

    let portal = PortalController()

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
        credentials = nil
        isEditing = true
        portal.status = .idle
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.isEditing || appState.credentials == nil {
            CredentialsView(existing: appState.credentials, onSave: appState.save)
        } else if let credentials = appState.credentials {
            DashboardView(controller: appState.portal, credentials: credentials)
        }
    }
}

@main
struct PUPSISPortalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .commands {
            CommandMenu("Account") {
                Button("Edit Credentials") { appState.isEditing = true }
                Button("Sign Out") { appState.signOut() }
                    .disabled(appState.credentials == nil)
            }
        }
    }
}
