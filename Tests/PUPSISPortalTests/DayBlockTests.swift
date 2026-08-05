import XCTest
@testable import PUPSISPortal

final class BlockLayoutTests: XCTestCase {
    private func block(_ id: String, _ start: Int, _ end: Int) -> DayBlock {
        DayBlock(id: id, day: .monday, start: start, end: end, title: id, subtitle: "")
    }

    private func lanes(_ placements: [BlockLayout.Placement], _ id: String) -> (lane: Int, lanes: Int)? {
        placements.first { $0.block.title == id }.map { ($0.lane, $0.lanes) }
    }

    func testEmptyDayPlacesNothing() {
        XCTAssertTrue(BlockLayout.arrange([]).isEmpty)
    }

    func testASingleBlockTakesTheFullWidth() {
        let placements = BlockLayout.arrange([block("a", 540, 660)])

        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(lanes(placements, "a")?.lanes, 1)
        XCTAssertEqual(lanes(placements, "a")?.lane, 0)
    }

    /// The whole reason this exists: two blocks at the same hour must not draw
    /// on top of each other.
    func testOverlappingBlocksSplitTheWidth() {
        let placements = BlockLayout.arrange([block("a", 540, 660), block("b", 600, 720)])

        XCTAssertEqual(lanes(placements, "a")?.lanes, 2)
        XCTAssertEqual(lanes(placements, "b")?.lanes, 2)
        XCTAssertNotEqual(lanes(placements, "a")?.lane, lanes(placements, "b")?.lane)
    }

    /// 3–6pm followed by 6–9pm is consecutive, not concurrent. Treating a
    /// shared edge as an overlap would halve two classes that never collide.
    func testTouchingEdgesAreNotAnOverlap() {
        let placements = BlockLayout.arrange([block("a", 900, 1080), block("b", 1080, 1260)])

        XCTAssertEqual(lanes(placements, "a")?.lanes, 1)
        XCTAssertEqual(lanes(placements, "b")?.lanes, 1)
    }

    /// A busy morning must not shrink an unrelated afternoon block.
    func testSeparateClustersAreSizedIndependently() {
        let placements = BlockLayout.arrange([
            block("morningA", 480, 600),
            block("morningB", 540, 660),
            block("afternoon", 840, 960),
        ])

        XCTAssertEqual(lanes(placements, "morningA")?.lanes, 2)
        XCTAssertEqual(lanes(placements, "afternoon")?.lanes, 1)
    }

    /// Three-way pileup, and the third block reuses the lane the first freed.
    func testLanesAreReusedOnceABlockHasEnded() {
        let placements = BlockLayout.arrange([
            block("a", 480, 540),
            block("b", 500, 700),
            block("c", 560, 620),
        ])

        // a and b overlap, c overlaps b but starts after a ends.
        XCTAssertEqual(lanes(placements, "b")?.lanes, 2)
        XCTAssertEqual(lanes(placements, "a")?.lane, 0)
        XCTAssertEqual(lanes(placements, "c")?.lane, 0)
        XCTAssertEqual(lanes(placements, "b")?.lane, 1)
    }

    func testEveryBlockIsPlacedExactlyOnce() {
        let input = [block("a", 480, 600), block("b", 540, 660), block("c", 900, 960)]

        let placements = BlockLayout.arrange(input)

        XCTAssertEqual(placements.count, input.count)
        XCTAssertEqual(Set(placements.map(\.block.id)), Set(input.map(\.id)))
    }
}

final class GridAxisTests: XCTestCase {
    private func block(_ start: Int, _ end: Int) -> DayBlock {
        DayBlock(id: "\(start)-\(end)", day: .monday, start: start, end: end, title: "x", subtitle: "")
    }

    func testAnEmptyWeekStillShowsTheNormalDay() {
        XCTAssertEqual(GridAxis.hours(covering: []).start, 6 * 60)
        XCTAssertEqual(GridAxis.hours(covering: []).end, 22 * 60)
    }

    /// A schedule sitting inside 6am–10pm must not shrink the grid to fit it,
    /// or the layout changes shape every time the timetable does.
    func testABusyDayInsideTheWindowDoesNotShrinkIt() {
        let axis = GridAxis.hours(covering: [block(8 * 60, 10 * 60), block(13 * 60, 18 * 60)])

        XCTAssertEqual(axis.start, 6 * 60)
        XCTAssertEqual(axis.end, 22 * 60)
    }

    func testAnEarlyClassPushesTheTopOut() {
        let axis = GridAxis.hours(covering: [block(5 * 60 + 30, 7 * 60)])

        XCTAssertEqual(axis.start, 5 * 60)
        XCTAssertEqual(axis.end, 22 * 60)
    }

    func testALateClassPushesTheBottomOut() {
        let axis = GridAxis.hours(covering: [block(20 * 60, 22 * 60 + 30)])

        XCTAssertEqual(axis.start, 6 * 60)
        XCTAssertEqual(axis.end, 23 * 60)
    }

    /// Both edges at once, and neither may clip its block.
    func testTheAxisNeverClipsABlock() {
        let blocks = [block(4 * 60 + 15, 6 * 60), block(21 * 60, 23 * 60 + 45)]
        let axis = GridAxis.hours(covering: blocks)

        XCTAssertLessThanOrEqual(axis.start, blocks.map(\.start).min()!)
        XCTAssertGreaterThanOrEqual(axis.end, blocks.map(\.end).max()!)
    }

    /// Hour rules and gutter labels are drawn per hour; a ragged edge would
    /// put the first label off the top of the grid.
    func testEdgesLandOnWholeHours() {
        let axis = GridAxis.hours(covering: [block(5 * 60 + 30, 22 * 60 + 1)])

        XCTAssertEqual(axis.start % 60, 0)
        XCTAssertEqual(axis.end % 60, 0)
    }
}

final class DayBlockTests: XCTestCase {
    private let session = ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                                       faculty: "SANTOS, JUAN", day: .tuesday,
                                       start: 14 * 60, end: 16 * 60)

    func testAClassCarriesItsSessionThrough() {
        let block = DayBlock(session)

        XCTAssertEqual(block.day, .tuesday)
        XCTAssertEqual(block.start, 14 * 60)
        XCTAssertEqual(block.end, 16 * 60)
        XCTAssertEqual(block.title, "COMP 20073")
        XCTAssertEqual(block.session, session)
    }

    /// An event has no session — anything reading one back must get nil rather
    /// than a stand-in, or event blocks would grow class-only controls.
    func testAnEventHasNoSession() {
        let block = DayBlock(id: "abc", day: .monday, start: 600, end: 660,
                             title: "Dentist", subtitle: "10AM – 11AM")

        XCTAssertNil(block.session)
        XCTAssertEqual(block.source, .calendarEvent(identifier: "abc"))
    }

    /// Ids are namespaced: a class and an event could otherwise collide and
    /// SwiftUI would reuse the wrong view.
    func testClassAndEventIdsCannotCollide() {
        let event = DayBlock(id: session.id, day: .tuesday, start: 14 * 60, end: 16 * 60,
                             title: "Decoy", subtitle: "")

        XCTAssertNotEqual(DayBlock(session).id, event.id)
    }
}
