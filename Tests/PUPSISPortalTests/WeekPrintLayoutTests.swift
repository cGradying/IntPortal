import XCTest
@testable import PUPSISPortal

/// The print view itself isn't meaningfully unit-testable — these pin the
/// pure layout math it's built on, the same functions the live grid uses.
final class WeekPrintLayoutTests: XCTestCase {
    private func classBlock(_ day: Weekday, _ start: Int, _ end: Int) -> DayBlock {
        DayBlock(ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                              faculty: "SANTOS, JUAN", day: day, start: start, end: end))
    }

    func testAxisMatchesTheLiveGridsWrapper() {
        let blocks = [classBlock(.monday, 8 * 60, 10 * 60)]
        XCTAssertEqual(
            WeekPrintLayout.axis(for: blocks).start,
            GridAxis.hours(covering: blocks).start
        )
        XCTAssertEqual(
            WeekPrintLayout.axis(for: blocks).end,
            GridAxis.hours(covering: blocks).end
        )
    }

    /// An empty week still gets a sane default window rather than a
    /// zero-height page.
    func testAnEmptyWeekFallsBackToTheDefaultWindow() {
        let height = WeekPrintLayout.bodyHeight(for: [])
        let hours = CGFloat(GridAxis.defaultWindow.end - GridAxis.defaultWindow.start) / 60
        XCTAssertEqual(height, hours * WeekPrintLayout.hourHeight, accuracy: 0.01)
    }

    /// A class outside the default 6am–10pm window pushes the page taller
    /// rather than getting clipped — same guarantee `GridAxis` gives the grid.
    func testALateClassGrowsThePageRatherThanClipping() {
        let normal = WeekPrintLayout.bodyHeight(for: [classBlock(.monday, 8 * 60, 9 * 60)])
        let late = WeekPrintLayout.bodyHeight(for: [classBlock(.monday, 8 * 60, 9 * 60), classBlock(.tuesday, 22 * 60, 23 * 60)])
        XCTAssertGreaterThan(late, normal)
    }

    /// A later class must sit visually below an earlier one on the page.
    func testALaterClassSitsBelowAnEarlierOneInTheGeometry() {
        let blocks = [classBlock(.monday, 8 * 60, 9 * 60), classBlock(.monday, 11 * 60, 12 * 60)]
        let geometry = WeekPrintLayout.geometry(for: blocks)

        let early = geometry.rect(day: .monday, start: 8 * 60, end: 9 * 60)
        let late = geometry.rect(day: .monday, start: 11 * 60, end: 12 * 60)
        XCTAssertLessThan(early.minY, late.minY)
    }

    /// Overlapping classes get distinct lanes rather than drawing on top of
    /// each other — the exact reuse of `BlockLayout` the print view relies on.
    func testOverlappingBlocksGetSeparateLanes() {
        let blocks = [classBlock(.monday, 8 * 60, 10 * 60), classBlock(.monday, 9 * 60, 11 * 60)]
        let placements = BlockLayout.arrange(blocks)

        XCTAssertEqual(placements.count, 2)
        XCTAssertEqual(Set(placements.map(\.lane)), [0, 1])
        XCTAssertTrue(placements.allSatisfy { $0.lanes == 2 })
    }

    func testPageSizeAccountsForGutterAndMargins() {
        let blocks = [classBlock(.monday, 8 * 60, 9 * 60)]
        let size = WeekPrintLayout.pageSize(for: blocks)

        XCTAssertEqual(size.width, WeekPrintLayout.gutter + WeekPrintLayout.bodyWidth + WeekPrintLayout.margin * 2, accuracy: 0.01)
        XCTAssertGreaterThan(size.height, WeekPrintLayout.bodyHeight(for: blocks))
    }
}
