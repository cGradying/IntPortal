import XCTest
@testable import PUPSISPortal

final class GridGeometryTests: XCTestCase {
    /// 7 columns of 100pt with 5pt gaps = 730pt wide. 960pt tall over a
    /// 16-hour axis is one point per minute, which keeps the arithmetic here
    /// readable.
    private let grid = GridGeometry(
        width: 730,
        height: 960,
        axis: (start: 6 * 60, end: 22 * 60),
        columnSpacing: 5
    )

    func testColumnsDivideTheWidthEvenly() {
        XCTAssertEqual(grid.columnWidth, 100, accuracy: 0.001)
    }

    func testEachDayStartsWhereTheLastColumnEnded() {
        XCTAssertEqual(grid.x(of: .monday), 0, accuracy: 0.001)
        XCTAssertEqual(grid.x(of: .tuesday), 105, accuracy: 0.001)
        XCTAssertEqual(grid.x(of: .sunday), 630, accuracy: 0.001)
    }

    func testAPointResolvesToItsOwnColumn() {
        XCTAssertEqual(grid.day(atX: 0), .monday)
        XCTAssertEqual(grid.day(atX: 50), .monday)
        XCTAssertEqual(grid.day(atX: 110), .tuesday)
        XCTAssertEqual(grid.day(atX: 680), .sunday)
    }

    /// Dragging off either edge should keep selecting the end column rather
    /// than falling off the grid.
    func testPointsOutsideTheGridClampToTheEndColumns() {
        XCTAssertEqual(grid.day(atX: -500), .monday)
        XCTAssertEqual(grid.day(atX: 5000), .sunday)
    }

    func testAZeroWidthGridDoesNotDivideByZero() {
        let empty = GridGeometry(width: 0, height: 0, axis: (start: 0, end: 60))
        XCTAssertEqual(empty.day(atX: 40), .monday)
    }

    // MARK: Drag ranges

    func testASingleColumnDragCoversOneDay() {
        let range = grid.drag(from: CGPoint(x: 40, y: 480), to: CGPoint(x: 60, y: 600))

        XCTAssertEqual(range.days, [.monday])
        XCTAssertFalse(range.isMultiDay)
        XCTAssertEqual(range.start, 14 * 60)
        XCTAssertEqual(range.end, 16 * 60)
    }

    func testDraggingRightCoversEveryColumnBetween() {
        let range = grid.drag(from: CGPoint(x: 40, y: 480), to: CGPoint(x: 260, y: 600))

        XCTAssertEqual(range.days, [.monday, .tuesday, .wednesday])
        XCTAssertTrue(range.isMultiDay)
    }

    /// Dragging right-to-left has to mean the same days as left-to-right.
    func testDraggingLeftCoversTheSameDays() {
        let rightward = grid.drag(from: CGPoint(x: 40, y: 480), to: CGPoint(x: 260, y: 600))
        let leftward = grid.drag(from: CGPoint(x: 260, y: 600), to: CGPoint(x: 40, y: 480))

        XCTAssertEqual(leftward.days, rightward.days)
        XCTAssertEqual(leftward.start, rightward.start)
        XCTAssertEqual(leftward.end, rightward.end)
    }

    /// The event is stored starting on the first day; the rest come from the
    /// recurrence rule, so the anchor must be the earliest weekday.
    func testTheAnchorDayIsTheEarliestRegardlessOfDragDirection() {
        let leftward = grid.drag(from: CGPoint(x: 470, y: 480), to: CGPoint(x: 40, y: 600))

        XCTAssertEqual(leftward.anchorDay, .monday)
    }

    func testDragsAcrossTheWholeWeekCoverAllSevenDays() {
        let range = grid.drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 730, y: 960))

        XCTAssertEqual(range.days, Weekday.allCases)
    }

    // MARK: Rects

    func testABlockRectMatchesItsColumnAndTimes() {
        let rect = grid.rect(day: .tuesday, start: 14 * 60, end: 16 * 60)

        XCTAssertEqual(rect.minX, 105, accuracy: 0.001)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 480, accuracy: 0.001)
        XCTAssertEqual(rect.height, 120, accuracy: 0.001)
    }

    /// A zero-length block would give the editor popover nothing to anchor to.
    func testAZeroLengthBlockStillHasHeight() {
        let rect = grid.rect(day: .monday, start: 9 * 60, end: 9 * 60)

        XCTAssertGreaterThan(rect.height, 0)
    }

    func testRubberBandCoversTheColumnsItTouches() {
        let band = CGRect(x: 60, y: 100, width: 200, height: 300)

        XCTAssertEqual(grid.days(in: band), [.monday, .tuesday, .wednesday])
    }
}
