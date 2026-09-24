import AppKit
import SwiftUI

/// One reminder per class meeting.
struct NotificationsPane: View {
    @ObservedObject var preferences: Preferences
    /// For rescheduling reminders after a change — same reason `AppearancePane`
    /// takes `sessions` instead of a live `PortalController`.
    let sessions: [ClassSession]

    @ObservedObject private var notifier = Notifier.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(
                title: "Notifications",
                footer: """
                One reminder per class meeting, repeating weekly. Meetings you've \
                marked vacant are skipped. Reminders fire only while PUPSISPortal is \
                running — turn on Start at login (General) so it's always there to \
                fire them, even after a restart.
                """
            ) {
                SettingsRow(label: "Remind me before class") {
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

                SettingsRow(label: "How early") {
                    Picker("", selection: $preferences.notificationLeadMinutes) {
                        ForEach(Preferences.leadOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes before").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                    .disabled(!preferences.notificationsEnabled)
                    .onChange(of: preferences.notificationLeadMinutes) { syncNotifications() }
                }

                if notifier.authorization == .denied {
                    SettingsRow(label: "Notifications are turned off for this app") {
                        Button("Open System Settings…") {
                            guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                            else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.pixelSmall)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            SettingsResetButton {
                preferences.notificationsEnabled = false
                preferences.notificationLeadMinutes = 15
            }

            SettingsTechnicalSection(rows: [
                ("Authorization status", notifier.authorization.map { "\($0)" } ?? "unknown"),
                ("Lead time", "\(preferences.notificationLeadMinutes) minutes"),
                ("Start at login", LoginItem.isEnabled ? "enabled" : "disabled"),
            ])
        }
        .task { await notifier.refreshAuthorization() }
    }

    private func syncNotifications() {
        Task {
            // Same reasoning as `AppState.refresh()`: `sync` unconditionally
            // clears every pending reminder before deciding whether to re-add
            // any, and with `authorization` still `nil`/stale that check
            // fails and wipes every reminder with nothing put back. Refresh
            // first.
            await notifier.refreshAuthorization()
            notifier.sync(sessions, preferences)
        }
    }
}
