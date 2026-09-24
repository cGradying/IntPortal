import AppKit
import ServiceManagement
import SwiftUI

/// Launch/window behavior, the island (spec 12), motion, the notes database
/// location, and the two destructive resets, last.
struct GeneralPane: View {
    @ObservedObject var preferences: Preferences
    /// Deletes every note/folder/pasted image — routed as a closure rather
    /// than a `NotesStore` instance, so a snapshot test never has to
    /// construct one just to render this pane.
    let onWipeNotes: () -> Void

    /// Mirrors the OS login-item status; re-read after every toggle so it
    /// can't drift from System Settings.
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmingWipe = false
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Window", footer: "The launch portal, the red/yellow/green window buttons, and launching with your Mac.") {
                SettingsRow(label: "Play portal intro") {
                    Toggle("", isOn: $preferences.playPortalIntro).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Auto-hide window buttons") {
                    Toggle("", isOn: $preferences.trafficLightsAutoHide).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Start at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, wants in
                            LoginItem.setEnabled(wants)
                            // Reflect what actually took effect, in case registration failed.
                            launchAtLogin = LoginItem.isEnabled
                        }
                }
                SettingsRow(label: "Open on") {
                    Picker("", selection: $preferences.launchDestination) {
                        ForEach(LaunchDestination.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                }
            }

            SettingsSection(
                title: "Island",
                footer: "The floating pill above the content column: the current screen's glance and controls."
            ) {
                SettingsRow(label: "Show the island") {
                    Toggle("", isOn: $preferences.showIsland).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Expand on hover") {
                    Toggle("", isOn: $preferences.islandExpandOnHover).labelsHidden().toggleStyle(.switch)
                        .disabled(!preferences.showIsland)
                }
            }

            SettingsSection(
                title: "Motion",
                footer: "Turns off every animation in the app, whatever System Settings says: portals, screen changes, stamps and cards."
            ) {
                SettingsRow(label: "Force Reduce Motion") {
                    Toggle("", isOn: $preferences.forceReducedMotion).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsSection(
                title: "Notes Database",
                footer: "Opens Finder with notes.json selected — the file everything in Notes is stored in."
            ) {
                SettingsRow(label: "Notes storage") {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([NotesStore.defaultURL])
                    }
                    .buttonStyle(.pixelSmall)
                }
            }

            SettingsResetButton {
                preferences.trafficLightsAutoHide = true
                preferences.forceReducedMotion = false
                preferences.playPortalIntro = true
                preferences.showIsland = true
                preferences.islandExpandOnHover = true
                preferences.launchDestination = .hub
            }

            SettingsSection(
                title: "Wipe Notes",
                footer: "Deletes every note, folder, and pasted image. Login, schedule/grades cache, and settings are untouched."
            ) {
                SettingsRow(label: "Every note") {
                    Button("Delete All Notes…", role: .destructive) { confirmingWipe = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .confirmationDialog("Delete all notes?", isPresented: $confirmingWipe) {
                Button("Delete Everything", role: .destructive, action: onWipeNotes)
            } message: {
                Text("This deletes every note, folder, and pasted image. This cannot be undone.")
            }

            SettingsSection(
                title: "Danger Zone",
                footer: "Resets every setting in this app — theme, AI configuration, calendar exports, notification preferences, everything each pane's own controls expose — back to first-launch defaults. Per-class colors, online/vacant marks, moved times, notes, and syllabus tasks, plus your schedule cache, notes, and quiz decks, are untouched."
            ) {
                SettingsRow(label: "Every setting") {
                    Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
                Button("Reset Everything", role: .destructive) { preferences.resetAllToDefaults() }
            } message: {
                Text("This resets every setting to its default. This cannot be undone.")
            }

            SettingsTechnicalSection(rows: [
                ("App Support directory", NotesStore.defaultURL.deletingLastPathComponent().path),
                ("Login item status", "\(SMAppService.mainApp.status)"),
            ])
        }
    }
}
