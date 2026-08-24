import XCTest
@testable import PUPSISPortal

final class BlockLayoutTests: XCTestCase {
    private func block(_ id: String, _ start: Int, _ end: Int) -> DayBlock {
        DayBlock(id: id, day: .monday, start: start, end: end, title: id, subtitle: "")
    }

    private func classBlock(_ id: String, _ start: Int, _ end: Int) -> DayBlock {
        DayBlock(ClassSession(subjectCode: id, description: "", faculty: "", day: .monday, start: start, end: end))
    }

    private func placement(_ placements: [BlockLayout.Placement], _ id: String) -> BlockLayout.Placement? {
        placements.first { $0.block.title == id }
    }

    func testEmptyDayPlacesNothing() {
        XCTAssertTrue(BlockLayout.arrange([]).isEmpty)
    }

    func testASingleBlockTakesTheFullWidth() {
        let placements = BlockLayout.arrange([block("a", 540, 660)])

        XCTAssertEqual(placements.count, 1)
        XCTAssertTrue(placement(placements, "a")!.isFullWidth)
    }

    /// The whole reason this exists: two blocks at the same hour must not draw
    /// on top of each other.
    func testOverlappingBlocksSplitTheWidth() {
        let placements = BlockLayout.arrange([block("a", 540, 660), block("b", 600, 720)])

        XCTAssertEqual(placement(placements, "a")?.width, 0.5)
        XCTAssertEqual(placement(placements, "b")?.width, 0.5)
        XCTAssertNotEqual(placement(placements, "a")?.offset, placement(placements, "b")?.offset)
    }

    /// 3–6pm followed by 6–9pm is consecutive, not concurrent. Treating a
    /// shared edge as an overlap would halve two classes that never collide.
    func testTouchingEdgesAreNotAnOverlap() {
        let placements = BlockLayout.arrange([block("a", 900, 1080), block("b", 1080, 1260)])

        XCTAssertTrue(placement(placements, "a")!.isFullWidth)
        XCTAssertTrue(placement(placements, "b")!.isFullWidth)
    }

    /// A busy morning must not shrink an unrelated afternoon block.
    func testSeparateClustersAreSizedIndependently() {
        let placements = BlockLayout.arrange([
            block("morningA", 480, 600),
            block("morningB", 540, 660),
            block("afternoon", 840, 960),
        ])

        XCTAssertEqual(placement(placements, "morningA")?.width, 0.5)
        XCTAssertTrue(placement(placements, "afternoon")!.isFullWidth)
    }

    /// Three-way pileup, and the third block reuses the lane the first freed.
    func testLanesAreReusedOnceABlockHasEnded() {
        let placements = BlockLayout.arrange([
            block("a", 480, 540),
            block("b", 500, 700),
            block("c", 560, 620),
        ])

        // a and b overlap, c overlaps b but starts after a ends.
        XCTAssertEqual(placement(placements, "a")?.width, 0.5)
        XCTAssertEqual(placement(placements, "b")?.width, 0.5)
        XCTAssertEqual(placement(placements, "c")?.width, 0.5)
        XCTAssertEqual(placement(placements, "a")?.offset, placement(placements, "c")?.offset)
        XCTAssertNotEqual(placement(placements, "a")?.offset, placement(placements, "b")?.offset)
    }

    /// A class and an event at the same hour split the width exactly the
    /// same way as two classes — no nesting, no front/behind relationship.
    func testAClassAndAnEventOverlappingJustSplitTheWidth() {
        let placements = BlockLayout.arrange([
            block("event", 0, 1000),
            classBlock("class", 100, 300),
        ])

        XCTAssertEqual(placement(placements, "event")?.width, 0.5)
        XCTAssertEqual(placement(placements, "class")?.width, 0.5)
    }

    func testEveryBlockIsPlacedExactlyOnce() {
        let input = [block("a", 480, 600), block("b", 540, 660), block("c", 900, 960)]

        let placements = BlockLayout.arrange(input)

        XCTAssertEqual(placements.count, input.count)
        XCTAssertEqual(Set(placements.map(\.block.id)), Set(input.map(\.id)))
    }
}

final class BlockRunsTests: XCTestCase {
    private func event(_ title: String, _ day: Weekday, _ start: Int = 840, _ end: Int = 960) -> DayBlock {
        DayBlock(id: "\(title)-\(day.rawValue)", day: day, start: start, end: end,
                 title: title, subtitle: "")
    }

    private func session(_ code: String, _ day: Weekday, _ start: Int = 840, _ end: Int = 960) -> DayBlock {
        DayBlock(ClassSession(subjectCode: code, description: "", faculty: "",
                              day: day, start: start, end: end))
    }

    func testALoneBlockIsItsOwnRun() {
        let block = event("Study", .wednesday)

        XCTAssertEqual(BlockRuns.positions(for: [block])[block.id], .single)
    }

    /// The case that prompted this: a drag from Monday to Wednesday drew three
    /// unconnected boxes.
    func testConsecutiveDaysFormOneRun() {
        let blocks = [event("Study", .monday), event("Study", .tuesday), event("Study", .wednesday)]

        let positions = BlockRuns.positions(for: blocks)

        XCTAssertEqual(positions[blocks[0].id], .leading)
        XCTAssertEqual(positions[blocks[1].id], .middle)
        XCTAssertEqual(positions[blocks[2].id], .trailing)
    }

    /// The real path `WeekGrid.blockLayer` takes, not just `BlockRuns` in
    /// isolation: each day is arranged on its own (`BlockLayout.arrange`
    /// only ever sees one day's blocks at a time), the results are gated
    /// through `isFullWidth`, and only what survives that gate reaches
    /// `BlockRuns.positions`. A recurring event with no overlap on any of
    /// its five days should still bridge across all of them.
    func testARecurringEventWithNoOverlapBridgesThroughTheRealPipeline() {
        let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let blocks = days.map { event("Home practice", $0, 690, 990) }

        let placed = Weekday.allCases.flatMap { day in
            BlockLayout.arrange(blocks.filter { $0.day == day })
        }
        let bridgeable = Set(placed.filter { $0.isFullWidth }.map(\.block.id))
        let positions = BlockRuns.positions(for: blocks.filter { bridgeable.contains($0.id) })

        XCTAssertEqual(positions[blocks[0].id], .leading)
        XCTAssertEqual(positions[blocks[1].id], .middle)
        XCTAssertEqual(positions[blocks[2].id], .middle)
        XCTAssertEqual(positions[blocks[3].id], .middle)
        XCTAssertEqual(positions[blocks[4].id], .trailing)
    }

    /// The exact shape image 14 reported: Wednesday's occurrence of the
    /// recurring event was edited "this event only", which detaches it in
    /// EventKit — it loses `hasRecurrenceRules`, so `CalendarBridge` falls
    /// back to the time-keyed `groupKey`, genuinely different from the
    /// series' `"series-<identifier>"` the other four still share
    /// (`Core/CalendarBridge.swift:223`). That's a legitimate break — two
    /// 2-day runs, not one 5-day run — but only Monday and Thursday (the
    /// *start* of each sub-run) should show the leading stripe; Tuesday and
    /// Friday should read as seamlessly joined to the day before them.
    func testADetachedMidWeekOccurrenceSplitsIntoTwoRunsNotFiveSingles() {
        let recurring: [Weekday] = [.monday, .tuesday, .thursday, .friday]
        var blocks = recurring.map { event("Home practice", $0, 690, 990) }
        // Wednesday: same title, different time, own groupKey — detached.
        blocks.append(event("Home practice", .wednesday, 645, 945))

        let placed = Weekday.allCases.flatMap { day in
            BlockLayout.arrange(blocks.filter { $0.day == day })
        }
        let bridgeable = Set(placed.filter { $0.isFullWidth }.map(\.block.id))
        let positions = BlockRuns.positions(for: blocks.filter { bridgeable.contains($0.id) })

        let byDay = Dictionary(uniqueKeysWithValues: blocks.map { ($0.day, $0.id) })
        XCTAssertEqual(positions[byDay[.monday]!], .leading)
        XCTAssertEqual(positions[byDay[.tuesday]!], .trailing)
        XCTAssertEqual(positions[byDay[.thursday]!], .leading)
        XCTAssertEqual(positions[byDay[.friday]!], .trailing)
    }

    func testATwoDayRunHasNoMiddle() {
        let blocks = [event("Study", .thursday), event("Study", .friday)]
        let positions = BlockRuns.positions(for: blocks)

        XCTAssertEqual(positions[blocks[0].id], .leading)
        XCTAssertEqual(positions[blocks[1].id], .trailing)
    }

    /// Bridging Monday to Wednesday would draw a bar straight through a
    /// Tuesday the class doesn't meet on.
    func testNonConsecutiveDaysDoNotJoin() {
        let blocks = [session("COMP 001", .monday), session("COMP 001", .wednesday),
                      session("COMP 001", .friday)]

        for block in blocks {
            XCTAssertEqual(BlockRuns.positions(for: blocks)[block.id], .single, block.day.short)
        }
    }

    /// Two subjects at the same hour on adjacent days are unrelated.
    func testDifferentThingsNeverJoin() {
        let blocks = [session("COMP 001", .monday), session("GEED 005", .tuesday)]

        XCTAssertEqual(BlockRuns.positions(for: blocks)[blocks[0].id], .single)
        XCTAssertEqual(BlockRuns.positions(for: blocks)[blocks[1].id], .single)
    }

    /// Same subject, different hour — a run means the same slot across days.
    func testTheSameSubjectAtADifferentHourIsADifferentRun() {
        let blocks = [session("COMP 001", .monday, 480, 600), session("COMP 001", .tuesday, 840, 960)]

        XCTAssertEqual(BlockRuns.positions(for: blocks)[blocks[0].id], .single)
        XCTAssertEqual(BlockRuns.positions(for: blocks)[blocks[1].id], .single)
    }

    /// Two runs of the same thing in one week each get their own ends.
    func testAGapSplitsOneGroupIntoTwoRuns() {
        let blocks = [event("Study", .monday), event("Study", .tuesday),
                      event("Study", .thursday), event("Study", .friday)]
        let positions = BlockRuns.positions(for: blocks)

        XCTAssertEqual(positions[blocks[0].id], .leading)
        XCTAssertEqual(positions[blocks[1].id], .trailing)
        XCTAssertEqual(positions[blocks[2].id], .leading)
        XCTAssertEqual(positions[blocks[3].id], .trailing)
    }

    /// Sunday closes the week. Joining it to Monday would draw a bar off the
    /// right edge of the grid and back in on the left.
    func testTheWeekDoesNotWrapFromSundayToMonday() {
        let blocks = [event("Study", .sunday), event("Study", .monday)]
        let positions = BlockRuns.positions(for: blocks)

        XCTAssertEqual(positions[blocks[0].id], .single)
        XCTAssertEqual(positions[blocks[1].id], .single)
    }

    /// The far end of the week does join normally.
    func testSaturdayAndSundayJoin() {
        let blocks = [event("Study", .saturday), event("Study", .sunday)]
        let positions = BlockRuns.positions(for: blocks)

        XCTAssertEqual(positions[blocks[0].id], .leading)
        XCTAssertEqual(positions[blocks[1].id], .trailing)
    }

    /// Only the ends round, so the joins read as one continuous bar.
    func testOnlyTheOuterCornersOfARunAreRounded() {
        XCTAssertTrue(RunPosition.single.roundsLeft && RunPosition.single.roundsRight)
        XCTAssertTrue(RunPosition.leading.roundsLeft)
        XCTAssertFalse(RunPosition.leading.roundsRight)
        XCTAssertFalse(RunPosition.middle.roundsLeft || RunPosition.middle.roundsRight)
        XCTAssertTrue(RunPosition.trailing.roundsRight)
    }

    /// Everything but the last block reaches across the column gap.
    func testOnlyTheLastBlockOfARunStopsAtItsColumn() {
        XCTAssertTrue(RunPosition.leading.bridgesRight)
        XCTAssertTrue(RunPosition.middle.bridgesRight)
        XCTAssertFalse(RunPosition.trailing.bridgesRight)
        XCTAssertFalse(RunPosition.single.bridgesRight)
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
