import SwiftUI

/// Version, update checks, authorship, and terms of use.
struct AboutPane: View {
    @ObservedObject var updaterBridge: UpdaterBridge
    let canCheckForUpdates: Bool
    @Binding var automaticallyChecksForUpdates: Bool
    let onCheckForUpdates: () -> Void

    /// Read through `UpdateCheck` so the version shown here and the version
    /// the update check compares against can't drift apart. Unknown when
    /// there's no Info.plist to read (a bare `swift run`) — better than a
    /// hardcoded stand-in, which silently goes stale at the next release.
    private var appVersion: String { UpdateCheck.currentVersion ?? "unknown" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "About") {
                SettingsRow(label: "IntPortal") {
                    HStack(spacing: 8) {
                        Text(updaterBridge.availableVersion.map { "v\(appVersion) — v\($0) available" } ?? "v\(appVersion)")
                            .foregroundStyle(.secondary)
                        Button("Check for Updates…", action: onCheckForUpdates)
                            .buttonStyle(.pixelSmall).font(.caption)
                            .disabled(!canCheckForUpdates)
                    }
                }
                SettingsRow(label: "Check for updates automatically") {
                    Toggle("", isOn: $automaticallyChecksForUpdates).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Author") { Text("Janvin D. Salvador").foregroundStyle(.secondary) }
                SettingsRow(label: "Contact") {
                    Link("cgradying@gmail.com", destination: URL(string: "mailto:cgradying@gmail.com")!)
                        .font(.callout)
                }
                SettingsRow(label: "LinkedIn") {
                    // ponytail: people-search link (safe) until the exact profile URL is known.
                    Link("Janvin D. Salvador",
                         destination: URL(string: "https://www.linkedin.com/search/results/people/?keywords=Janvin%20D.%20Salvador")!)
                        .font(.callout)
                }
            }

            SettingsSection(title: "Support") {
                SettingsRow(label: "Donate") { Text("Coming soon").foregroundStyle(.secondary) }
            }

            SettingsSection(title: "Terms of Use") {
                Text("""
                IntPortal is an unofficial, independent client for the PUP \
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
            }

            SettingsTechnicalSection(rows: [
                ("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"),
                ("Bundle identifier", Bundle.main.bundleIdentifier ?? "unknown"),
                ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            ])
        }
    }
}
