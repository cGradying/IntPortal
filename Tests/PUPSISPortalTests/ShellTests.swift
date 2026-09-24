import SwiftUI
import XCTest
@testable import PUPSISPortal

final class DestinationTests: XCTestCase {
    func testShortcutsFollowSpec01() {
        let keys = Dictionary(uniqueKeysWithValues: Destination.allCases.map { ($0, $0.shortcut.character) })
        XCTAssertEqual(keys, [.schedule: "1", .today: "2", .grades: "3", .notebook: "4", .quizzes: "5", .syllabus: "6"])
    }

    func testDepthFollowsSidebarOrder() {
        XCTAssertEqual(Destination.allCases, [.today, .schedule, .grades, .notebook, .quizzes, .syllabus])
        XCTAssertEqual(Destination.direction(from: .today, to: .grades), 1)
        XCTAssertEqual(Destination.direction(from: .syllabus, to: .schedule), -1)
    }

    func testStudyScreensAreGrouped() {
        XCTAssertEqual(Destination.allCases.filter(\.isStudy), [.notebook, .quizzes, .syllabus])
    }

    @MainActor
    func testSyncLineCopy() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(ShellSidebar.sync(host: "sis8", lastUpdated: nil, failed: false, now: now).line, "sis8 · not synced yet")
        XCTAssertEqual(ShellSidebar.sync(host: "sis8", lastUpdated: nil, failed: true, signInFailed: true, now: now).line, "Couldn't sign in · Check your details")
        XCTAssertEqual(ShellSidebar.sync(host: "sis8", lastUpdated: now, failed: true, now: now),
                       SyncStatus(line: "Couldn't reach SIS · Try again", failed: true))
        XCTAssertTrue(ShellSidebar.sync(host: "sis8", lastUpdated: now.addingTimeInterval(-3 * 3600), failed: false, now: now).line.hasPrefix("sis8 · updated 3"))
    }

    func testScheduleHeaderCountsTheWeek() {
        let wednesday = Date(timeIntervalSince1970: 1_790_150_400) // Wed 2026-09-23 UTC-ish
        let session = ClassSession(subjectCode: "COMP 002", description: "", faculty: "", day: Weekday.on(wednesday), start: 540, end: 720)
        XCTAssertEqual(ScreenCopy.context(for: .today, now: wednesday, sessions: [session], weekOffset: 0), "1 class today")
        XCTAssertEqual(ScreenCopy.context(for: .today, now: wednesday, sessions: [], weekOffset: 0), "No classes today")
        XCTAssertEqual(ScreenCopy.title(for: .schedule, now: wednesday), "Class schedule")
    }
}

/// The shell as the window draws it, minus live state: sidebar, header and
/// an empty sheet where the screen goes.
private struct ShellPreview: View {
    let selection: Destination
    let failed: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                selection: selection, studentNumber: "2026-00000-MN-0",
                sync: failed ? SyncStatus(line: "Couldn't reach SIS · Try again", failed: true) : SyncStatus(line: "sis8 · updated 3 hr. ago", failed: false),
                updateVersion: "2.0.0", onSelect: { _ in }, onSettings: {}, onRetry: {}, dragArea: false
            )
            .frame(width: 236)
            VStack(spacing: 0) {
                ScreenHeader(title: "Grades", context: "Your posted grades, term by term", crumb: "Grades")
                Sheet(label: "Second semester, 2025–2026", meta: "GPA 1.23") {
                    Text("Sample content").padding(Spacing.lg)
                }
                .padding(Spacing.xxl)
                Spacer(minLength: 0)
            }
            .background(palette.roles.ground)
        }
        .frame(width: 1100, height: 640)
    }
}

@MainActor
final class ShellSnapshotTests: XCTestCase {
    func testShellRendersInBothPalettesAndScales() throws {
        let light = try Snapshot.render(ShellPreview(selection: .grades, failed: false), name: "shell-light", palette: .registrar, scheme: .light)
        try Snapshot.render(ShellPreview(selection: .grades, failed: true), name: "shell-dark-failed", palette: .registrarNight, scheme: .dark)
        for scale in [0.8, 1.4] {
            try Snapshot.render(ShellPreview(selection: .today, failed: false), name: "shell-\(Int(scale * 100))", palette: .registrar, scheme: .light, scale: scale)
        }
        XCTAssertEqual(light.size, CGSize(width: 1100, height: 640))
    }
}
