import AppKit
import SwiftUI
import Inject

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

/// The slice of `AppState` the panel below actually reads. Small enough that
/// a snapshot test can satisfy it with a plain fake instead of constructing a
/// real `AppState` — whose `init` reads the Keychain and starts Sparkle's
/// updater, neither of which a test may touch.
protocol MenuBarSource: ObservableObject {
    var credentials: Credentials? { get }
    var now: Date { get }
    var sessions: [ClassSession] { get }
    var upcoming: NextClass.Upcoming? { get }
    func refresh() async
}

extension AppState: MenuBarSource {
    var sessions: [ClassSession] { portal.sessions }
}

/// The dropdown. Next class up top, the rest of today under it, then the
/// controls that make a windowless app usable: open, refresh, quit. Styled as
/// a small Registrar sheet — notch, hairline, sunk rows — the same grammar as
/// every other surface in the app (`08-menu-bar.md`).
struct MenuBarPanel<Source: MenuBarSource>: View {
    @ObserveInjection var inject
    @ObservedObject var appState: Source
    @ObservedObject var preferences: Preferences
    /// The footer's campus chip text (e.g. "MN · Sta. Mesa"), supplied once
    /// the campus resolver lands (`10-campus.md`, not merged yet). `nil`
    /// renders nothing, so the footer is unchanged until then.
    var campusChip: String? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var systemScheme

    private var palette: Palette { preferences.theme.palette(for: systemScheme) }
    private var typography: Typography { Typography(preferences.fontChoice) }

    var body: some View {
        let roles = palette.roles
        VStack(alignment: .leading, spacing: 12) {
            if appState.credentials == nil {
                Text("Sign in to see your schedule.")
                    .font(typography.reading(size: 12))
                    .foregroundStyle(roles.ink3)
            } else {
                dateHeader

                let upcoming = appState.upcoming
                if let upcoming {
                    nextClass(upcoming)
                } else {
                    Text("No more classes this week.")
                        .font(typography.reading(size: 12))
                        .foregroundStyle(roles.ink3)
                }

                let rest = laterToday(after: upcoming)
                if !rest.isEmpty {
                    hairline
                    laterList(rest)
                } else if let first = todayAgenda.tomorrowFirst, isWindingDownToday(upcoming) {
                    // The day's last class is up next — look ahead to tomorrow.
                    hairline
                    tomorrowLine(first)
                }
            }

            hairline
            reminderStatus
            hairline
            footer
        }
        .padding(14)
        .frame(width: 260)
        .background(roles.sheet, in: PixelNotch())
        .overlay(PixelNotch().strokeBorder(roles.line, lineWidth: 1))
        .environment(\.palette, palette)
        .environment(\.typography, typography)
        .enableInjection()
    }

    // MARK: Sections

    private var hairline: some View {
        Rectangle().fill(palette.roles.line).frame(height: 1)
    }

    private var dateHeader: some View {
        Text(appState.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .font(typography.numeric(size: 11, weight: .semibold))
            .foregroundStyle(palette.roles.ink3)
    }

    private func nextClass(_ upcoming: NextClass.Upcoming) -> some View {
        let roles = palette.roles
        let color = preferences.color(for: upcoming.session.subjectCode, in: palette)
        let status = preferences.status(for: upcoming.session, on: Weekday.weekStart(containing: appState.now))
        return HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(color).frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Up next")
                        .font(typography.numeric(size: 10, weight: .semibold))
                        .foregroundStyle(roles.ink3)
                    // The gold now marker: the one hue that ever marks the
                    // present moment (DESIGN.md's Now Rule).
                    if upcoming.isNow {
                        Rectangle().fill(roles.gold).frame(width: 6, height: 6)
                    }
                }
                HStack(spacing: 6) {
                    // The code sits in the display face, tinted with the
                    // subject colour — same identity the class block uses.
                    Text(upcoming.session.subjectCode)
                        .font(typography.display(size: 16, weight: .bold))
                        .foregroundStyle(color)
                    if status == .online {
                        Stamp(kind: .online, subject: color, small: true)
                    }
                }
                Text(upcoming.session.description)
                    .font(typography.reading(size: 12))
                    .foregroundStyle(roles.ink2)
                    .lineLimit(1)
                Text(upcoming.countdown(now: appState.now))
                    .font(typography.numeric(size: 11, weight: .semibold))
                    .foregroundStyle(upcoming.isNow ? roles.goldInk : roles.actionInk)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func laterList(_ items: [DayAgenda.Item]) -> some View {
        let roles = palette.roles
        return VStack(alignment: .leading, spacing: 6) {
            Text("Later today")
                .font(typography.numeric(size: 10, weight: .semibold))
                .foregroundStyle(roles.ink3)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    laterRow(item)
                }
            }
            .background(roles.sunk, in: PixelNotch())
        }
    }

    private func laterRow(_ item: DayAgenda.Item) -> some View {
        let roles = palette.roles
        let color = preferences.color(for: item.session.subjectCode, in: palette)
        let status = preferences.status(for: item.session, on: Weekday.weekStart(containing: appState.now))
        return HStack(spacing: 8) {
            if item.phase == .inSession {
                Rectangle().fill(roles.gold).frame(width: 6, height: 6)
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(item.session.subjectCode)
                .font(typography.display(size: 13, weight: .regular))
                .foregroundStyle(color)
            if item.phase == .inSession {
                Text("now")
                    .font(typography.numeric(size: 10, weight: .semibold))
                    .foregroundStyle(roles.goldInk)
            }
            if status != .regular {
                Stamp(kind: status == .online ? .online : .vacant, subject: color, small: true)
            }
            Spacer(minLength: 8)
            Text(ClassSession.format(item.start))
                .font(typography.numeric(size: 11))
                .foregroundStyle(roles.ink3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(item, status: status))
    }

    private func rowAccessibilityLabel(_ item: DayAgenda.Item, status: SessionStatus) -> String {
        let when = item.phase == .inSession ? "now" : "at \(ClassSession.format(item.start))"
        let state = status == .regular ? "" : ", \(status.label)"
        return "\(item.session.subjectCode), \(when)\(state)"
    }

    private func tomorrowLine(_ first: ClassSession) -> some View {
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: appState.now) ?? appState.now
        let start = preferences.time(for: first, on: Weekday.weekStart(containing: tomorrowDate)).start
        return HStack(spacing: 8) {
            Image(systemName: "sunrise")
                .foregroundStyle(palette.roles.ink3)
            Text("Tomorrow · \(first.subjectCode) at \(ClassSession.format(start))")
                .font(typography.reading(size: 12))
                .foregroundStyle(palette.roles.ink3)
        }
    }

    @ViewBuilder
    private var reminderStatus: some View {
        let roles = palette.roles
        HStack(spacing: 6) {
            Image(systemName: preferences.notificationsEnabled ? "bell.fill" : "bell.slash")
                .foregroundStyle(roles.ink3)
            Text(preferences.notificationsEnabled
                 ? "Reminders on · \(preferences.notificationLeadMinutes) min before"
                 : "Reminders off")
                .font(typography.reading(size: 12))
                .foregroundStyle(roles.ink3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(roles.sunk, in: PixelNotch())
    }

    @ViewBuilder
    private var footer: some View {
        let roles = palette.roles
        VStack(alignment: .leading, spacing: 8) {
            if let campusChip {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 10))
                    Text(campusChip).font(typography.numeric(size: 10, weight: .semibold))
                }
                .foregroundStyle(roles.ink2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(roles.sunk, in: PixelNotch())
                .accessibilityLabel("Campus, \(campusChip)")
            }
            controls
        }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: PUPSISPortalApp.mainWindowID)
            } label: {
                Label("Open IntPortal", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.pixelPrimary)

            Button {
                Task { await appState.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(typography.reading(size: 12))
            .disabled(appState.credentials == nil)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(typography.reading(size: 12))
        }
    }

    // MARK: Today's remaining classes

    /// The one reading of today, shared with the Today screen. Used here only
    /// for the tomorrow look-ahead, which still skips a class vacant this
    /// week exactly as it always has.
    private var todayAgenda: DayAgenda {
        DayAgenda.make(
            sessions: appState.sessions,
            now: appState.now,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            },
            time: { session, date in
                preferences.time(for: session, on: Weekday.weekStart(containing: date))
            }
        )
    }

    /// Today's classes including ones marked vacant this week — "Later
    /// today" stamps a vacant meeting instead of hiding it, so the panel
    /// reads the same status the grid does rather than making it disappear.
    private var visibleAgenda: DayAgenda {
        DayAgenda.make(
            sessions: appState.sessions,
            now: appState.now,
            isVacant: { _, _ in false },
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
            return visibleAgenda.remaining
        }
        return visibleAgenda.remaining.filter { $0.session.id != upcoming.session.id }
    }

    /// True when there's a class today but the next one is its last — the moment
    /// a look-ahead to tomorrow is useful.
    private func isWindingDownToday(_ upcoming: NextClass.Upcoming?) -> Bool {
        guard let upcoming else { return false }
        return upcoming.session.day == Weekday.on(appState.now)
    }
}
