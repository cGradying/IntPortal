import XCTest
@testable import PUPSISPortal

final class TimeSnapTests: XCTestCase {
    private let axis = (start: 6 * 60, end: 22 * 60)

    func testSnappingGoesToTheNearestQuarterHour() {
        XCTAssertEqual(TimeSnap.snap(0), 0)
        XCTAssertEqual(TimeSnap.snap(7), 0)
        XCTAssertEqual(TimeSnap.snap(8), 15)
        XCTAssertEqual(TimeSnap.snap(22), 15)
        XCTAssertEqual(TimeSnap.snap(23), 30)
    }

    func testTheTopAndBottomOfTheGridMapToTheAxisEdges() {
        XCTAssertEqual(TimeSnap.minutes(atY: 0, axis: axis, height: 960), axis.start)
        XCTAssertEqual(TimeSnap.minutes(atY: 960, axis: axis, height: 960), axis.end)
    }

    /// 960pt over a 16-hour axis is one point per minute, so halfway down is
    /// eight hours in — 2pm.
    func testAPointInTheMiddleMapsToTheMiddleOfTheDay() {
        XCTAssertEqual(TimeSnap.minutes(atY: 480, axis: axis, height: 960), 14 * 60)
    }

    func testDraggingOffTheEndsIsClampedToTheGrid() {
        XCTAssertEqual(TimeSnap.minutes(atY: -400, axis: axis, height: 960), axis.start)
        XCTAssertEqual(TimeSnap.minutes(atY: 4000, axis: axis, height: 960), axis.end)
    }

    func testAZeroHeightGridDoesNotDivideByZero() {
        XCTAssertEqual(TimeSnap.minutes(atY: 50, axis: axis, height: 0), axis.start)
    }

    // MARK: Drag ranges

    func testDraggingDownwardsProducesThatRange() {
        let range = TimeSnap.range(from: 9 * 60, to: 11 * 60, axis: axis)

        XCTAssertEqual(range.start, 9 * 60)
        XCTAssertEqual(range.end, 11 * 60)
    }

    /// Dragging upward has to mean the same thing as dragging downward.
    func testDraggingUpwardsProducesTheSameRange() {
        let up = TimeSnap.range(from: 11 * 60, to: 9 * 60, axis: axis)
        let down = TimeSnap.range(from: 9 * 60, to: 11 * 60, axis: axis)

        XCTAssertEqual(up.start, down.start)
        XCTAssertEqual(up.end, down.end)
    }

    /// A click without movement should still create something usable rather
    /// than a zero-length block.
    func testAStationaryDragStillMakesAMinimumEvent() {
        let range = TimeSnap.range(from: 9 * 60, to: 9 * 60, axis: axis)

        XCTAssertEqual(range.end - range.start, TimeSnap.minimumDuration)
    }

    /// At the very bottom of the day there's no room to grow downward, so it
    /// has to grow upward instead of producing nothing.
    func testAtTheBottomOfTheDayTheMinimumGrowsUpwards() {
        let range = TimeSnap.range(from: axis.end, to: axis.end, axis: axis)

        XCTAssertEqual(range.end, axis.end)
        XCTAssertEqual(range.end - range.start, TimeSnap.minimumDuration)
        XCTAssertGreaterThanOrEqual(range.start, axis.start)
    }

    // MARK: Resizing

    func testDraggingTheBottomEdgeMovesOnlyTheEnd() {
        let resized = TimeSnap.resize(start: 9 * 60, end: 10 * 60,
                                      movingEdge: .bottom, to: 12 * 60, axis: axis)

        XCTAssertEqual(resized.start, 9 * 60)
        XCTAssertEqual(resized.end, 12 * 60)
    }

    func testDraggingTheTopEdgeMovesOnlyTheStart() {
        let resized = TimeSnap.resize(start: 9 * 60, end: 12 * 60,
                                      movingEdge: .top, to: 8 * 60, axis: axis)

        XCTAssertEqual(resized.start, 8 * 60)
        XCTAssertEqual(resized.end, 12 * 60)
    }

    /// Dragging an edge past the opposite one must not invert the block.
    func testAnEdgeCannotBeDraggedThroughTheOther() {
        let bottom = TimeSnap.resize(start: 9 * 60, end: 12 * 60,
                                     movingEdge: .bottom, to: 7 * 60, axis: axis)
        XCTAssertEqual(bottom.end - bottom.start, TimeSnap.minimumDuration)

        let top = TimeSnap.resize(start: 9 * 60, end: 12 * 60,
                                  movingEdge: .top, to: 20 * 60, axis: axis)
        XCTAssertEqual(top.end - top.start, TimeSnap.minimumDuration)
    }

    func testResizingIsClampedToTheGrid() {
        let above = TimeSnap.resize(start: 9 * 60, end: 12 * 60,
                                    movingEdge: .top, to: 0, axis: axis)
        XCTAssertEqual(above.start, axis.start)

        let below = TimeSnap.resize(start: 9 * 60, end: 12 * 60,
                                    movingEdge: .bottom, to: 30 * 60, axis: axis)
        XCTAssertEqual(below.end, axis.end)
    }
}
