import SwiftUI

/// Settings as a screen (spec 07): a pane list down the left, the selected
/// pane's sheets on the right. Reached from the sidebar's System group or
/// ⌘, (`AppShell`/`AppState.open(.settings)`) — no longer a sheet over the
/// window, so every dependency below is a plain value or a narrow callback
/// rather than the whole `AppState`, the same decomposition `CalendarView`
/// already uses, and what lets `SettingsSnapshotTests` render a pane without
/// constructing a real `AppState` (Keychain, Sparkle) in a test.
struct SettingsScreen: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var portal: PortalController
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var googleAuth: GoogleAuth
    let googleClient: GoogleCalendarClient
    @ObservedObject var updaterBridge: UpdaterBridge
    let canCheckForUpdates: Bool
    @Binding var automaticallyChecksForUpdates: Bool
    let onCheckForUpdates: () -> Void
    let onWipeNotes: () -> Void
    let onEditCredentials: () -> Void
    let onSignOut: () -> Void
    let onRefreshSchedule: () -> Void
    let onShowHub: () -> Void

    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, schedule, notifications, intelligence, storage, account, about
        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .schedule: "Schedule"
            case .notifications: "Notifications"
            case .intelligence: "Intelligence"
            case .storage: "Storage"
            case .account: "Account"
            case .about: "About"
            }
        }

        var glyph: PixelIcon.Glyph {
            switch self {
            case .general: .gear
            case .appearance: .spark2
            case .schedule: .week
            case .notifications: .bulb
            case .intelligence: .spark
            case .storage: .list
            case .account: .lock
            case .about: .help
            }
        }
    }

    @State private var pane: Pane = .general
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxl) {
            paneList
            ScrollView {
                paneContent
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.vertical, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var paneList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { item in
                let selected = pane == item
                Button {
                    withAnimation(Motion.selection(reduced: reduceMotion)) { pane = item }
                } label: {
                    HStack(spacing: 8) {
                        PixelIcon(item.glyph, size: 16)
                        Text(item.label).font(typography.reading(size: 14, weight: selected ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? palette.roles.action : palette.roles.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 168, alignment: .leading)
                    .background(selected ? palette.roles.actionSoft : .clear, in: PixelNotch())
                    .contentShape(PixelNotch())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.top, Spacing.lg)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general:
            GeneralPane(preferences: preferences, onWipeNotes: onWipeNotes)
        case .appearance:
            AppearancePane(preferences: preferences, sessions: portal.sessions)
        case .schedule:
            SchedulePane(preferences: preferences, calendar: calendar, googleAuth: googleAuth, googleClient: googleClient, sessions: portal.sessions)
        case .notifications:
            NotificationsPane(preferences: preferences, sessions: portal.sessions)
        case .intelligence:
            IntelligencePane(preferences: preferences)
        case .storage:
            StoragePane(preferences: preferences)
        case .account:
            AccountPane(preferences: preferences, portal: portal, onEditCredentials: onEditCredentials, onSignOut: onSignOut, onRefreshSchedule: onRefreshSchedule, onShowHub: onShowHub)
        case .about:
            AboutPane(
                updaterBridge: updaterBridge, canCheckForUpdates: canCheckForUpdates,
                automaticallyChecksForUpdates: $automaticallyChecksForUpdates, onCheckForUpdates: onCheckForUpdates
            )
        }
    }
}
