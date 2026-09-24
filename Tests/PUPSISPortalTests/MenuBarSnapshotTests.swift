import AppKit
import SwiftUI
import XCTest
@testable import PUPSISPortal

/// A fixed stand-in for `AppState`, satisfying `MenuBarSource` without
/// touching the Keychain or Sparkle the way a real `AppState()` would.
private final class FakeMenuBarSource: MenuBarSource {
    @Published var credentials: Credentials?
    @Published var now: Date
    @Published var sessions: [ClassSession]
    @Published var upcoming: NextClass.Upcoming?
    private(set) var refreshCount = 0

    init(
        now: Date,
        sessions: [ClassSession] = [],
        upcoming: NextClass.Upcoming? = nil,
        signedIn: Bool = true
    ) {
        self.now = now
        self.sessions = sessions
        self.upcoming = upcoming
        credentials = signedIn
            ? Credentials(studentNumber: "2026-00000-MN-0", birthMonth: 3, birthDay: 14, birthYear: 2007, password: "")
            : nil
    }

    func refresh() async { refreshCount += 1 }
}

/// Renders `MenuBarPanel` against fixed clocks and demo sessions — every
/// state the panel can be in, per `08-menu-bar.md` and PLAN-2's MB lanes.
@MainActor
final class MenuBarSnapshotTests: XCTestCase {
    // MARK: Fixtures

    /// Monday 2026-08-03 at `hour:minute`, local calendar — the same default
    /// calendar `MenuBarPanel` itself resolves weekdays against, so the panel
    /// and the fixture always agree on what day "today" is.
    private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: hour, minute: minute))!
    }

    private func tuesday(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: hour, minute: minute))!
    }

    private func session(_ code: String, _ day: Weekday, _ start: Int, _ end: Int) -> ClassSession {
        ClassSession(subjectCode: code, description: "Sample subject", faculty: "Prof. Sample", day: day, start: start, end: end)
    }

    private func upcoming(_ session: ClassSession, start: Date, isNow: Bool) -> NextClass.Upcoming {
        NextClass.Upcoming(session: session, start: start, startMinutes: session.start, endMinutes: session.end, isNow: isNow)
    }

    private func preferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "MenuBarSnapshotTests-\(UUID().uuidString)")!)
    }

    @discardableResult
    private func render(
        _ name: String, source: FakeMenuBarSource, preferences: Preferences,
        campusChip: String? = nil, scheme: ColorScheme = .light
    ) throws -> NSImage {
        try Snapshot.render(
            MenuBarPanel(appState: source, preferences: preferences, campusChip: campusChip),
            name: name, palette: scheme == .dark ? .registrarNight : .registrar, scheme: scheme
        )
    }

    // MARK: Lane 2 — a class in 12 minutes

    func testUpNextClassSoon() throws {
        let now = monday(9, 48)
        let comp002 = session("COMP 002", .monday, 600, 720) // 10:00–12:00
        let source = FakeMenuBarSource(
            now: now, sessions: [comp002],
            upcoming: upcoming(comp002, start: monday(10), isNow: false)
        )
        let image = try render("soon", source: source, preferences: preferences())
        XCTAssertGreaterThan(image.size.height, 50)
    }

    // MARK: Lane 3 — classes later today, one already "now"

    func testLaterTodayListsRemainingClassesWithNow() throws {
        let now = monday(10, 30)
        let comp001 = session("COMP 001", .monday, 600, 650) // 10:00–10:50, chosen as Up next
        let comp002 = session("COMP 002", .monday, 600, 700) // overlapping section, still in session
        let geed020 = session("GEED 020", .monday, 780, 870) // 1:00–2:30 PM, still ahead
        let source = FakeMenuBarSource(
            now: now, sessions: [comp001, comp002, geed020],
            upcoming: upcoming(comp001, start: monday(10), isNow: true)
        )
        let image = try render("later", source: source, preferences: preferences())
        XCTAssertGreaterThan(image.size.height, 50)
    }

    // MARK: Lane 4 — after the last class, tomorrow's first shows

    func testTomorrowLineAfterTodaysLastClass() throws {
        let now = monday(15, 30)
        let cwts = session("CWTS 001", .monday, 900, 960) // 3:00–4:00 PM, today's only/last class
        let geed005 = session("GEED 005", .tuesday, 540, 660) // tomorrow's first, 9:00–11:00 AM
        let source = FakeMenuBarSource(
            now: now, sessions: [cwts, geed005],
            upcoming: upcoming(cwts, start: monday(15), isNow: true)
        )
        let image = try render("tomorrow", source: source, preferences: preferences())
        XCTAssertGreaterThan(image.size.height, 50)
    }

    // MARK: Lane 5 — signed out

    func testSignedOut() throws {
        let source = FakeMenuBarSource(now: monday(9), signedIn: false)
        let image = try render("signed-out", source: source, preferences: preferences())
        XCTAssertGreaterThan(image.size.height, 20)
    }

    // MARK: Lane 6 — nothing left this week

    func testWeekEnd() throws {
        let source = FakeMenuBarSource(now: monday(18), sessions: [], upcoming: nil)
        let image = try render("week-end", source: source, preferences: preferences())
        XCTAssertGreaterThan(image.size.height, 20)
    }

    // MARK: Lane 7 — reminders on and off

    func testRemindersOnAndOff() throws {
        let now = monday(9, 48)
        let comp002 = session("COMP 002", .monday, 600, 720)
        let upcomingClass = upcoming(comp002, start: monday(10), isNow: false)

        let on = preferences()
        on.notificationsEnabled = true
        on.notificationLeadMinutes = 15
        try render("reminders-on", source: FakeMenuBarSource(now: now, sessions: [comp002], upcoming: upcomingClass), preferences: on)

        let off = preferences()
        off.notificationsEnabled = false
        try render("reminders-off", source: FakeMenuBarSource(now: now, sessions: [comp002], upcoming: upcomingClass), preferences: off)
    }

    // MARK: Lane 8 — dark

    func testDark() throws {
        let now = monday(10, 30)
        let comp001 = session("COMP 001", .monday, 600, 650)
        let geed020 = session("GEED 020", .monday, 780, 870)
        let source = FakeMenuBarSource(
            now: now, sessions: [comp001, geed020],
            upcoming: upcoming(comp001, start: monday(10), isNow: true)
        )
        let image = try render("dark", source: source, preferences: preferences(), scheme: .dark)
        XCTAssertGreaterThan(image.size.height, 50)
    }

    // MARK: Lane 10 — an online and a vacant class, each stamped

    func testOnlineAndVacantStamps() throws {
        let now = monday(10, 30)
        let comp002 = session("COMP 002", .monday, 600, 720) // 10:00 AM–12:00 PM, marked Online
        let geed020 = session("GEED 020", .monday, 780, 870) // 1:00–2:30 PM, marked Vacant
        let prefs = preferences()
        prefs.setTermStatus(.online, for: comp002)
        prefs.setTermStatus(.vacant, for: geed020)
        let source = FakeMenuBarSource(
            now: now, sessions: [comp002, geed020],
            upcoming: upcoming(comp002, start: monday(10), isNow: true)
        )
        let image = try render("stamps", source: source, preferences: prefs)
        XCTAssertGreaterThan(image.size.height, 50)
    }

    // MARK: Campus chip seam

    func testCampusChipRendersOnlyWhenSupplied() throws {
        let now = monday(9, 48)
        let comp002 = session("COMP 002", .monday, 600, 720)
        let source = FakeMenuBarSource(
            now: now, sessions: [comp002],
            upcoming: upcoming(comp002, start: monday(10), isNow: false)
        )
        let withChip = try render("campus-chip", source: source, preferences: preferences(), campusChip: "MN · Sta. Mesa")
        let withoutChip = try render("no-campus-chip", source: source, preferences: preferences(), campusChip: nil)
        XCTAssertGreaterThan(withChip.size.height, withoutChip.size.height)
    }
}
