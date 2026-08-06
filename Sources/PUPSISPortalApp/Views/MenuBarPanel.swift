import AppKit
import SwiftUI

/// The menu bar item itself: an icon, plus the next class when there is one.
/// Kept short — the menu bar is scarce space, so the countdown detail lives in
/// the panel, not here. Re-renders on the minute because `AppState.now` does.
struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if let upcoming = appState.upcoming {
            // A dot while a class is running, the calendar glyph while one's
            // merely coming up — a glance tells you which.
            Image(systemName: upcoming.isNow ? "circle.fill" : "calendar")
            Text(labelText(upcoming))
        } else {
            Image(systemName: "calendar")
        }
    }

    private func labelText(_ upcoming: NextClass.Upcoming) -> String {
        if upcoming.isNow { return upcoming.session.subjectCode }
        let minutes = upcoming.minutesAway(from: appState.now)
        // Under an hour, the countdown is the useful number; further out, the
        // clock time is.
        return minutes < 60
            ? "\(upcoming.session.subjectCode) · \(minutes)m"
            : "\(upcoming.session.subjectCode) · \(ClassSession.format(upcoming.session.start))"
    }
}

/// The dropdown. Next class up top, the rest of today under it, then the
/// controls that make a windowless app usable: open, refresh, quit.
struct MenuBarPanel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var systemScheme

    private var palette: Palette { preferences.theme.palette(for: systemScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.credentials == nil {
                Text("Sign in to see your schedule.")
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
            } else if let upcoming = appState.upcoming {
                nextClass(upcoming)
                let rest = laterToday(after: upcoming)
                if !rest.isEmpty {
                    Divider()
                    laterList(rest)
                }
            } else {
                Text("No more classes this week.")
                    .font(Theme.Typo.detailBody)
                    .foregroundStyle(.secondary)
            }

            Divider()
            reminderStatus
            Divider()
            controls
        }
        .padding(14)
        .frame(width: 260)
        .environment(\.palette, palette)
    }

    // MARK: Sections

    private func nextClass(_ upcoming: NextClass.Upcoming) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(preferences.color(for: upcoming.session.subjectCode, in: palette))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Up next")
                    .font(Theme.Typo.detailMeta)
                    .foregroundStyle(.secondary)
                Text(upcoming.session.subjectCode)
                    .font(Theme.Typo.detailTitle)
                Text(upcoming.session.description)
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(upcoming.countdown(now: appState.now))
                    .font(Theme.Typo.footer.weight(.medium))
                    .foregroundStyle(palette.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func laterList(_ sessions: [ClassSession]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Later today")
                .font(Theme.Typo.detailMeta)
                .foregroundStyle(.secondary)
            ForEach(sessions) { session in
                HStack(spacing: 8) {
                    Circle()
                        .fill(preferences.color(for: session.subjectCode, in: palette))
                        .frame(width: 6, height: 6)
                    Text(session.subjectCode)
                        .font(Theme.Typo.footer)
                    Spacer(minLength: 8)
                    Text(ClassSession.format(session.start))
                        .font(Theme.Typo.detailMeta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var reminderStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: preferences.notificationsEnabled ? "bell.fill" : "bell.slash")
                .foregroundStyle(.secondary)
            Text(preferences.notificationsEnabled
                 ? "Reminders on · \(preferences.notificationLeadMinutes) min before"
                 : "Reminders off")
                .font(Theme.Typo.footer)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: PUPSISPortalApp.mainWindowID)
            } label: {
                Label("Open PUPSISPortal", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await appState.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(appState.credentials == nil)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .font(Theme.Typo.detailBody)
    }

    // MARK: Today's remaining classes

    /// The classes still to come today, after the next one — so the panel reads
    /// as "now, then the rest of your day" rather than repeating the next class.
    private func laterToday(after upcoming: NextClass.Upcoming) -> [ClassSession] {
        let today = Weekday.on(appState.now)
        // Only when the next class is itself today; if it's tomorrow or next
        // week, there is no "later today".
        guard upcoming.session.day == today else { return [] }

        let vacant = preferences.vacantSessionIDs
        let nowMinutes = NowLine.minutes(of: appState.now)

        return appState.portal.sessions
            .filter { $0.day == today && !vacant.contains($0.id) }
            .filter { $0.start > upcoming.session.start || ($0.start == upcoming.session.start && $0.id != upcoming.session.id) }
            .filter { $0.end > nowMinutes }
            .sorted { $0.start < $1.start }
    }
}
