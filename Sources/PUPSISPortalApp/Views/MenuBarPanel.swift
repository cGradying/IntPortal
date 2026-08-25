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
            : "\(upcoming.session.subjectCode) · \(ClassSession.format(upcoming.startMinutes))"
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
    private var typography: Typography { Typography(preferences.fontChoice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.credentials == nil {
                Text("Sign in to see your schedule.")
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
            } else {
                dateHeader

                let upcoming = appState.upcoming
                if let upcoming {
                    nextClass(upcoming)
                } else {
                    Text("No more classes this week.")
                        .font(typography.detailBody)
                        .foregroundStyle(.secondary)
                }

                let rest = laterToday(after: upcoming)
                if !rest.isEmpty {
                    Divider()
                    laterList(rest)
                } else if let first = todayAgenda.tomorrowFirst, isWindingDownToday(upcoming) {
                    // The day's last class is up next — look ahead to tomorrow.
                    Divider()
                    tomorrowLine(first)
                }
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

    private var dateHeader: some View {
        Text(appState.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .font(typography.detailMeta)
            .foregroundStyle(.secondary)
    }

    private func nextClass(_ upcoming: NextClass.Upcoming) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(preferences.color(for: upcoming.session.subjectCode, in: palette))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Up next")
                    .font(typography.detailMeta)
                    .foregroundStyle(.secondary)
                Text(upcoming.session.subjectCode)
                    .font(typography.detailTitle)
                Text(upcoming.session.description)
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(upcoming.countdown(now: appState.now))
                    .font(typography.footer.weight(.medium))
                    .foregroundStyle(palette.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func laterList(_ items: [DayAgenda.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Later today")
                .font(typography.detailMeta)
                .foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(preferences.color(for: item.session.subjectCode, in: palette))
                        .frame(width: 6, height: 6)
                    Text(item.session.subjectCode)
                        .font(typography.footer)
                    if item.phase == .inSession {
                        Text("now")
                            .font(typography.detailMeta)
                            .foregroundStyle(palette.accent)
                    }
                    Spacer(minLength: 8)
                    Text(ClassSession.format(item.start))
                        .font(typography.detailMeta)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel(item))
            }
        }
    }

    private func rowAccessibilityLabel(_ item: DayAgenda.Item) -> String {
        let when = item.phase == .inSession ? "now" : "at \(ClassSession.format(item.start))"
        return "\(item.session.subjectCode), \(when)"
    }

    private func tomorrowLine(_ first: ClassSession) -> some View {
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: appState.now) ?? appState.now
        let start = preferences.time(for: first, on: Weekday.weekStart(containing: tomorrowDate)).start
        return HStack(spacing: 8) {
            Image(systemName: "sunrise")
                .foregroundStyle(.secondary)
            Text("Tomorrow · \(first.subjectCode) at \(ClassSession.format(start))")
                .font(typography.footer)
                .foregroundStyle(.secondary)
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
                .font(typography.footer)
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
        .font(typography.detailBody)
    }

    // MARK: Today's remaining classes

    /// The one reading of today, shared with the Today screen. Vacancy keys per
    /// week (and to the occurrence's own week for tomorrow), so a class marked
    /// vacant just this week drops here exactly as it does on the grid.
    private var todayAgenda: DayAgenda {
        DayAgenda.make(
            sessions: appState.portal.sessions,
            now: appState.now,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            },
            time: { session, date in
                preferences.time(for: session, on: Weekday.weekStart(containing: date))
            }
        )
    }

    /// The classes still to come today, after the next one — so the panel reads
    /// as "now, then the rest of your day" rather than repeating the next class.
    private func laterToday(after upcoming: NextClass.Upcoming?) -> [DayAgenda.Item] {
        // Drop the up-next class when it's today's, so it isn't listed twice.
        guard let upcoming, upcoming.session.day == Weekday.on(appState.now) else {
            return todayAgenda.remaining
        }
        return todayAgenda.remaining.filter { $0.session.id != upcoming.session.id }
    }

    /// True when there's a class today but the next one is its last — the moment
    /// a look-ahead to tomorrow is useful.
    private func isWindingDownToday(_ upcoming: NextClass.Upcoming?) -> Bool {
        guard let upcoming else { return false }
        return upcoming.session.day == Weekday.on(appState.now)
    }
}
