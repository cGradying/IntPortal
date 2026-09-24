import SwiftUI

/// The signed-in account: refresh, credentials, sign out, the campus pick
/// (spec 10), and the way back to the portal hub.
struct AccountPane: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var portal: PortalController
    let onEditCredentials: () -> Void
    let onSignOut: () -> Void
    let onRefreshSchedule: () -> Void
    let onShowHub: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Account") {
                SettingsRow(label: "Last updated") {
                    Text(portal.lastUpdated.map {
                        $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "Never")
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Refresh Schedule", action: onRefreshSchedule)
                    Button("Edit Credentials", action: onEditCredentials)
                    Spacer()
                    Button("Sign Out", role: .destructive, action: onSignOut)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            SettingsSection(
                title: "Campus",
                footer: "Read from your student number. Only the MN code is confirmed; pick yours if it's wrong. Every campus uses the same SIS."
            ) {
                SettingsRow(label: "Campus") {
                    let picked = preferences.campusOverride
                    Menu {
                        ForEach(CampusCatalog.all, id: \.self) { campus in
                            Button(campus.name) { preferences.pickCampus(campus) }
                        }
                    } label: {
                        Text(picked.map { "\($0.code.map { "\($0) · " } ?? "")\($0.name)" } ?? "Pick your campus")
                            .font(typography.reading(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.roles.sheet, in: PixelNotch())
                    .overlay(PixelNotch().strokeBorder(palette.roles.line2, lineWidth: 1))
                }
            }

            SettingsSection(title: "Portal") {
                SettingsRow(label: "Hub") {
                    Button("Back to the portal hub", action: onShowHub)
                        .buttonStyle(.pixelSmall)
                }
            }

            SettingsTechnicalSection(rows: [
                ("SIS endpoint", portal.currentHost),
                ("Keychain service", "ph.edu.pup.sis8.portal"),
            ])
        }
    }
}
