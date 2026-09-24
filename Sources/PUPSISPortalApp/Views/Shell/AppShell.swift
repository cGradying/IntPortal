import SwiftUI

/// The sidebar's screens, in sidebar order. That order is also depth: moving
/// down the list pushes the next screen forward, moving up drops it back.
enum Destination: String, CaseIterable, Identifiable {
    case today
    case schedule
    case grades
    case notebook
    case quizzes
    case syllabus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .schedule: "Schedule"
        case .grades: "Grades"
        case .notebook: "Notebook"
        case .quizzes: "Quizzes"
        case .syllabus: "Syllabus"
        }
    }

    var glyph: PixelIcon.Glyph {
        switch self {
        case .today: .today
        case .schedule: .week
        case .grades: .grades
        case .notebook: .book
        case .quizzes: .cards
        case .syllabus: .list
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .schedule: "1"
        case .today: "2"
        case .grades: "3"
        case .notebook: "4"
        case .quizzes: "5"
        case .syllabus: "6"
        }
    }

    /// Main (the SIS record) or Study (the student's own material).
    var isStudy: Bool { [.notebook, .quizzes, .syllabus].contains(self) }

    /// Today and the study screens still render `AgendaView`, each on its own
    /// face, until spec 04 gives Today a screen of its own.
    var notebookTab: NotebookTab? {
        switch self {
        case .today, .notebook: .vault
        case .quizzes: .quizzes
        case .syllabus: .syllabus
        case .schedule, .grades: nil
        }
    }

    static func direction(from old: Destination, to new: Destination) -> Int {
        let order = Array(allCases)
        return (order.firstIndex(of: new) ?? 0) >= (order.firstIndex(of: old) ?? 0) ? 1 : -1
    }
}

/// The signed-in window: the maroon sidebar on the left, and on the right the
/// screen under its SIS-style header. Screens change by pushing in depth along
/// the sidebar's order; a finished refresh ripples out from the portal glyph.
struct AppShell: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    let credentials: Credentials
    @Environment(\.palette) private var palette
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        HStack(spacing: 0) {
            ShellSidebar(appState: appState, portal: appState.portal, updater: appState.updaterBridge, studentNumber: credentials.studentNumber)
                .frame(width: 236 * uiScale)
            VStack(spacing: 0) {
                // Schedule's controls (paging, Week | COR | Year, Show
                // cancelled, New event, Refresh) used to sit in a toolbar row
                // here. They now live in `ScheduleControls`, placed directly
                // above the COR strip inside `CalendarView` until the IS
                // slice gives every screen a floating controls island — the
                // header keeps only the title and context line.
                ScreenHeader(
                    title: ScreenCopy.title(for: appState.selection, now: appState.now),
                    context: ScreenCopy.context(
                        for: appState.selection, now: appState.now,
                        sessions: appState.portal.sessions, weekOffset: appState.schedule.weekOffset
                    ),
                    crumb: appState.selection.title
                )
                ZStack {
                    screen(appState.selection)
                        .id(appState.selection)
                        .depthPush(direction: appState.navDirection, reduced: reduceMotion)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(Motion.depthPush(reduced: reduceMotion), value: appState.selection)
            }
            .background(palette.roles.ground)
            .overlay(alignment: .bottomLeading) {
                AssistantFloating(appState: appState, preferences: preferences, session: appState.assistant)
                    .padding(Spacing.lg)
            }
        }
        .ignoresSafeArea()
        // The shell, not any one screen, starts the session: the app opens on
        // Today, so waiting for Schedule to appear would never sign in.
        .task {
            if appState.portal.status == .idle { appState.portal.signIn(with: credentials) }
        }
        .syncRipple(trigger: appState.syncPulse, ok: appState.syncOK, from: CGPoint(x: 25 * uiScale, y: 52 * uiScale))
    }

    @ViewBuilder
    private func screen(_ destination: Destination) -> some View {
        switch destination {
        case .schedule:
            CalendarView(
                controller: appState.portal,
                preferences: preferences,
                calendar: appState.calendar,
                syllabus: appState.syllabus,
                credentials: credentials,
                schedule: appState.schedule,
                updaterBridge: appState.updaterBridge,
                onCheckForUpdates: { appState.updaterController.checkForUpdates(nil) },
                onEditCredentials: { appState.isEditing = true },
                settingsShowing: appState.showingSettings,
                isRefreshing: appState.isRefreshing,
                onRefresh: { Task { await appState.refresh() } }
            )
        case .grades:
            GradesView(controller: appState.portal, preferences: preferences)
        case .today, .notebook, .quizzes, .syllabus:
            AgendaView(
                appState: appState, preferences: preferences, calendar: appState.calendar,
                notes: appState.notes, quizzes: appState.quizzes, generation: appState.generation,
                notebook: appState.notebook
            )
        }
    }
}

/// Feeds `Sidebar` from live state; the sidebar itself stays a plain view.
struct ShellSidebar: View {
    @ObservedObject var appState: AppState
    @ObservedObject var portal: PortalController
    @ObservedObject var updater: UpdaterBridge
    let studentNumber: String

    var body: some View {
        Sidebar(
            selection: appState.selection,
            busy: appState.isRefreshing,
            studentNumber: studentNumber,
            sync: ShellSidebar.sync(
                host: portal.hostLabel, lastUpdated: portal.lastUpdated, failed: portal.refreshError != nil,
                signInFailed: { if case .failed = portal.status { true } else { false } }(), now: appState.now
            ),
            updateVersion: updater.availableVersion,
            onSelect: { appState.open($0) },
            onSettings: { appState.showingSettings = true },
            onRetry: {
                if case .failed = portal.status { appState.isEditing = true } else { Task { await appState.refresh() } }
            },
            onUpdate: { appState.updaterController.checkForUpdates(nil) },
            onHub: { appState.showHub() }
        )
    }

    static func sync(host: String, lastUpdated: Date?, failed: Bool, signInFailed: Bool = false, now: Date) -> SyncStatus {
        if signInFailed { return SyncStatus(line: "Couldn't sign in · Check your details", failed: true) }
        if failed { return SyncStatus(line: "Couldn't reach SIS · Try again", failed: true) }
        guard let lastUpdated else { return SyncStatus(line: "\(host) · not synced yet", failed: false) }
        return SyncStatus(line: "\(host) · updated \(relative.localizedString(for: lastUpdated, relativeTo: now))", failed: false)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
}

/// The screen's title, one line of context and the SIS breadcrumb, with the
/// screen's own controls in a toolbar row underneath.
struct ScreenHeader<Tools: View>: View {
    let title: String
    let context: String
    let crumb: String
    @ViewBuilder var tools: Tools
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        let roles = palette.roles
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(typography.display(size: 28, weight: .bold))
                        .foregroundStyle(roles.ink)
                    Text(context)
                        .font(typography.reading(size: 14))
                        .foregroundStyle(roles.ink2)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("Student Module")
                    Text("›").accessibilityHidden(true)
                    Text(crumb).fontWeight(.semibold).foregroundStyle(roles.ink2)
                }
                .font(typography.reading(size: 13))
                .foregroundStyle(roles.ink3)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Location: Student Module, \(crumb)")
            }
            tools
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(roles.line).frame(height: 1) }
    }
}

extension ScreenHeader where Tools == EmptyView {
    init(title: String, context: String, crumb: String) {
        self.init(title: title, context: context, crumb: crumb) { EmptyView() }
    }
}

/// Each screen's header copy.
enum ScreenCopy {
    static func title(for destination: Destination, now: Date) -> String {
        switch destination {
        case .today: day.string(from: now)
        case .schedule: "Class schedule"
        default: destination.title
        }
    }

    static func context(for destination: Destination, now: Date, sessions: [ClassSession], weekOffset: Int) -> String {
        switch destination {
        case .today:
            let count = sessions.filter { $0.day == Weekday.on(now) }.count
            return count == 0 ? "No classes today" : "\(count) class\(count == 1 ? "" : "es") today"
        case .schedule:
            let start = Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: Weekday.weekStart(containing: now)) ?? now
            return "Week of \(week.string(from: start)) · click a class to stamp its status"
        case .grades: return "Your posted grades, term by term"
        case .notebook: return "Notes filed by subject · select text to Ask AI"
        case .quizzes: return "Your decks and what is due"
        case .syllabus: return "Weeks, exams and grading, from your syllabi"
        }
    }

    private static var day: DateFormatter { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f }
    private static var week: DateFormatter { let f = DateFormatter(); f.dateFormat = "MMMM d"; return f }
}

