import SwiftUI
import XCTest
@testable import PUPSISPortal

/// Renders the SC1 rebuild — the notched blocks, the gold today wash and
/// now-line, and the COR strip — with demo data, light and dark.
///
/// `ImageRenderer` can't draw a `ScrollView` or an `NSViewRepresentable`, so
/// this renders `WeekGrid` on its own (`scrolls: false`) rather than the
/// full `CalendarView`, which also carries a `.task` that would sign in for
/// real off-screen. Neither the Keychain nor the network is touched:
/// `PortalController`/`CalendarBridge` are built the same
/// `hasCredentials: { false }` way `PortalControllerTests` already does, and
/// every session comes from `Demo`.
@MainActor
final class ScheduleSnapshotTests: XCTestCase {
    /// A Wednesday partway through Demo's sample week, so the now-line, the
    /// today wash and a mid-day "in session" class all have something to draw.
    private static let wednesday = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 30))!

    private static let weekStart = Weekday.weekStart(containing: wednesday)

    private func preferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "ScheduleSnapshotTests-\(UUID().uuidString)")!)
    }

    /// `Demo.sessions` plus one vacant and one online class, so the hatch and
    /// the stamps both show up in the same render.
    private func blocks(preferences: Preferences) -> [DayBlock] {
        var sessions = Demo.sessions
        let vacant = ClassSession(subjectCode: "PATHFIT 1", description: "Movement Competency Training", faculty: "Prof. Sample", day: .thursday, start: 840, end: 960)
        let online = ClassSession(subjectCode: "COMP 001", description: "Introduction to Computing", faculty: "Prof. Sample", day: .friday, start: 810, end: 990)
        preferences.setStatus(.vacant, for: vacant, on: Self.weekStart)
        preferences.setStatus(.online, for: online, on: Self.weekStart)
        sessions = sessions.filter { $0.id != vacant.id && $0.id != online.id } + [vacant, online]
        return sessions.map { DayBlock($0) }
    }

    /// `WeekGrid` alone paints no canvas fill — in the real screen that's
    /// `CalendarView`'s own `palette.canvasWash`, sitting behind it. Without
    /// this, both palettes rendered on the same white `ImageRenderer`
    /// backdrop, masking the light/dark difference these tests exist to
    /// catch (confirmed in the first render: `-dark` looked identical to
    /// `-light` apart from the blocks themselves).
    private struct OnCanvas<Content: View>: View {
        @ViewBuilder let content: () -> Content
        @Environment(\.palette) private var palette
        var body: some View { content().background(palette.canvasWash) }
    }

    private func grid(scale: Double = 1) throws -> some View {
        let prefs = preferences()
        let sessionBlocks = blocks(preferences: prefs)
        return OnCanvas {
            WeekGrid(
                blocks: sessionBlocks,
                weekStart: Self.weekStart,
                selection: [],
                recurringIDs: [],
                preferences: prefs,
                syllabus: SyllabusStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cor-snap-\(UUID().uuidString).json")),
                editing: nil,
                scrolls: false
            )
        }
        .frame(width: 1280 * scale, height: 1100 * scale)
    }

    func testWeekGridRendersInBothRegistrarPalettes() throws {
        let light = try Snapshot.render(try grid(), name: "schedule-week-light", palette: .registrar, scheme: .light)
        let dark = try Snapshot.render(try grid(), name: "schedule-week-dark", palette: .registrarNight, scheme: .dark)
        XCTAssertGreaterThan(light.size.width, 200)
        XCTAssertEqual(light.size, dark.size)
    }

    /// One selected block, so the 2pt inset subject-coloured ring shows too.
    func testWeekGridWithASelectionRenders() throws {
        let prefs = preferences()
        let blocks = blocks(preferences: prefs)
        let grid = OnCanvas {
            WeekGrid(
                blocks: blocks,
                weekStart: Self.weekStart,
                selection: Set(blocks.prefix(1).map(\.id)),
                recurringIDs: [],
                preferences: prefs,
                syllabus: SyllabusStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cor-snap-\(UUID().uuidString).json")),
                editing: nil,
                scrolls: false
            )
        }
        .frame(width: 1280, height: 1100)
        try Snapshot.render(grid, name: "schedule-selection", palette: .registrar, scheme: .light)
    }

    /// Spec 03 change 2, the COR strip above the grid: school year, semester
    /// and "Updated {time} from {host}", from data `PortalController` holds.
    func testCorStripRendersWithDemoData() throws {
        let controller = PortalController(
            defaults: UserDefaults(suiteName: "ScheduleSnapshotTests-portal-\(UUID().uuidString)")!,
            hasCredentials: { false }
        )
        controller.sessions = Demo.sessions
        controller.lastUpdated = Self.wednesday
        controller.grades = Demo.grades

        let strip = CORStrip(controller: controller)
        XCTAssertTrue(strip.updatedLabel.contains("from sis"), "expected the host in \"\(strip.updatedLabel)\"")
        try Snapshot.render(strip.frame(width: 900), name: "schedule-cor-strip", palette: .registrar, scheme: .light)
        try Snapshot.render(strip.frame(width: 900), name: "schedule-cor-strip-dark", palette: .registrarNight, scheme: .dark)
    }

    /// The description ("title") line only shows on a tall block — DESIGN.md's
    /// ≥ 90pt rule — so a short 30min block and a tall 3-hour block side by
    /// side should differ by exactly that line.
    func testShortBlockHidesTheDescriptionATallBlockShows() throws {
        let prefs = preferences()
        let short = ClassSession(subjectCode: "COMP 001", description: "Short lab", faculty: "", day: .monday, start: 540, end: 570)
        let tall = ClassSession(subjectCode: "COMP 002", description: "Long lecture block", faculty: "", day: .tuesday, start: 540, end: 720)
        let grid = OnCanvas {
            WeekGrid(
                blocks: [DayBlock(short), DayBlock(tall)],
                weekStart: Self.weekStart,
                selection: [],
                recurringIDs: [],
                preferences: prefs,
                syllabus: SyllabusStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cor-snap-\(UUID().uuidString).json")),
                editing: nil,
                scrolls: false
            )
        }
        .frame(width: 1280, height: 1100)
        try Snapshot.render(grid, name: "schedule-tall-vs-short", palette: .registrar, scheme: .light)
    }

    /// `ScheduleControls` on its own — no `AppState`/`ScheduleModel`, just
    /// `.constant` bindings — proving it really does drop into any container
    /// per the coordinator's scope change, ahead of the IS slice's island.
    func testScheduleControlsRendersStandalone() throws {
        let week = ScheduleControls(
            scale: .constant(.week), showCancelled: .constant(true), weekOffset: 1,
            isRefreshing: false, onStep: { _ in }, onToday: {}, onNewEvent: {}, onRefresh: {}
        )
        .frame(width: 900)
        try Snapshot.render(week, name: "schedule-controls-week", palette: .registrar, scheme: .light)

        let refreshing = ScheduleControls(
            scale: .constant(.year), showCancelled: .constant(false), weekOffset: 0,
            isRefreshing: true, onStep: { _ in }, onToday: {}, onNewEvent: {}, onRefresh: {}
        )
        .frame(width: 900)
        try Snapshot.render(refreshing, name: "schedule-controls-year-refreshing", palette: .registrarNight, scheme: .dark)
    }
}
