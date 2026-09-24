import SwiftUI
import XCTest
@testable import PUPSISPortal

/// Every Settings pane, rendered on its own with demo data — same contract
/// `CampusSnapshotTests`/`ShellSnapshotTests` use: a plain view over values,
/// no live `AppState`. Panes have no `ScrollView` of their own (only
/// `SettingsScreen` wraps them in one), so none needs a `scrolls: false`
/// escape hatch for `ImageRenderer`.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    private func freshPreferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "SettingsSnapshotTests-\(UUID().uuidString)")!)
    }

    private func renderBoth<V: View>(_ name: String, @ViewBuilder _ view: () -> V) throws {
        let content = view().frame(width: 640).padding(Spacing.lg)
        try Snapshot.render(content, name: name, palette: .registrar, scheme: .light)
        try Snapshot.render(content, name: "\(name)-dark", palette: .registrarNight, scheme: .dark)
    }

    func testGeneralPane() throws {
        try renderBoth("settings-general") {
            GeneralPane(preferences: freshPreferences(), onWipeNotes: {})
        }
    }

    func testAppearancePane() throws {
        try renderBoth("settings-appearance") {
            AppearancePane(preferences: freshPreferences(), sessions: Demo.sessions)
        }
    }

    func testSchedulePane() throws {
        let googleAuth = GoogleAuth { "" }
        try renderBoth("settings-schedule") {
            SchedulePane(
                preferences: freshPreferences(), calendar: CalendarBridge(), googleAuth: googleAuth,
                googleClient: GoogleCalendarClient(auth: googleAuth), sessions: Demo.sessions
            )
        }
    }

    func testNotificationsPane() throws {
        try renderBoth("settings-notifications") {
            NotificationsPane(preferences: freshPreferences(), sessions: Demo.sessions)
        }
    }

    func testIntelligencePane() throws {
        try renderBoth("settings-intelligence") {
            IntelligencePane(preferences: freshPreferences())
        }
    }

    func testStoragePane() throws {
        try renderBoth("settings-storage") {
            StoragePane(preferences: freshPreferences())
        }
    }

    func testAccountPane() throws {
        let portal = PortalController()
        portal.lastUpdated = .now
        try renderBoth("settings-account") {
            AccountPane(
                preferences: freshPreferences(), portal: portal,
                onEditCredentials: {}, onSignOut: {}, onRefreshSchedule: {}, onShowHub: {}
            )
        }
    }

    func testAboutPane() throws {
        try renderBoth("settings-about") {
            AboutPane(
                updaterBridge: UpdaterBridge(), canCheckForUpdates: true,
                automaticallyChecksForUpdates: .constant(true), onCheckForUpdates: {}
            )
        }
    }

    /// The whole screen: pane list plus the (default) General pane, so the
    /// two-column layout itself — not just each pane's own content — gets a
    /// light/dark check.
    func testFullScreenOnGeneral() throws {
        let googleAuth = GoogleAuth { "" }
        let portal = PortalController()
        portal.sessions = Demo.sessions
        portal.lastUpdated = .now
        let screen = SettingsScreen(
            preferences: freshPreferences(), portal: portal, calendar: CalendarBridge(), googleAuth: googleAuth,
            googleClient: GoogleCalendarClient(auth: googleAuth), updaterBridge: UpdaterBridge(),
            canCheckForUpdates: true, automaticallyChecksForUpdates: .constant(true), onCheckForUpdates: {},
            onWipeNotes: {}, onEditCredentials: {}, onSignOut: {}, onRefreshSchedule: {}, onShowHub: {},
            scrolls: false // ImageRenderer can't draw ScrollView content.
        )
        // Tall enough for General's full (unscrolled) content — General is
        // the default pane and the tallest of the eight.
        .frame(width: 1100, height: 1500)
        let light = try Snapshot.render(screen, name: "settings-screen", palette: .registrar, scheme: .light)
        try Snapshot.render(screen, name: "settings-screen-dark", palette: .registrarNight, scheme: .dark)
        XCTAssertEqual(light.size, CGSize(width: 1100, height: 1500))
    }
}
