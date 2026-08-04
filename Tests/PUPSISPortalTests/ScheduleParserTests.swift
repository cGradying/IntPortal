import XCTest
@testable import PUPSISPortal

/// Cases are the real schedule lines scraped from the live SIS page.
final class ScheduleParserTests: XCTestCase {
    private func parse(_ line: String) -> [ClassSession] {
        ScheduleParser.parse([
            "subjectCode": "TEST 001",
            "description": "Test Subject",
            "faculty": "SANTOS, JUAN",
            "scheduleLine": line,
        ])
    }

    func testTwoDaysPairWithTheirOwnTimes() {
        let sessions = parse("1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].day, .tuesday)
        XCTAssertEqual(sessions[0].start, 14 * 60)
        XCTAssertEqual(sessions[0].end, 16 * 60)
        XCTAssertEqual(sessions[1].day, .friday)
        XCTAssertEqual(sessions[1].start, 13 * 60 + 30)
        XCTAssertEqual(sessions[1].end, 16 * 60 + 30)
    }

    func testSameDayTwiceBecomesTwoBlocks() {
        let sessions = parse("1N - BSCS 1-1N - SUN/SUN 08:00AM-12:00PM/01:00PM-06:00PM")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.day == .sunday })
        XCTAssertEqual(sessions[0].start, 8 * 60)
        XCTAssertEqual(sessions[0].end, 12 * 60)
        XCTAssertEqual(sessions[1].start, 13 * 60)
        XCTAssertEqual(sessions[1].end, 18 * 60)
    }

    func testSingleDaySingleRange() {
        let sessions = parse("1N - BSCS 1-1N - S 07:30AM-10:30AM")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].day, .saturday)
        XCTAssertEqual(sessions[0].start, 7 * 60 + 30)
        XCTAssertEqual(sessions[0].end, 10 * 60 + 30)
    }

    /// `TH` and `SUN` must win over the single-letter `T`/`S` codes.
    func testMultiLetterDayCodesArentSwallowed() {
        XCTAssertEqual(parse("1N - X - TH 09:00AM-11:00AM").first?.day, .thursday)
        XCTAssertEqual(parse("1N - X - SUN 09:00AM-11:00AM").first?.day, .sunday)
    }

    func testNoonAndMidnightBoundaries() {
        let noon = parse("1N - X - M 12:00PM-01:00PM")
        XCTAssertEqual(noon.first?.start, 12 * 60)
        XCTAssertEqual(noon.first?.end, 13 * 60)

        let earlyMorning = parse("1N - X - M 12:30AM-01:30AM")
        XCTAssertEqual(earlyMorning.first?.start, 30)
        XCTAssertEqual(earlyMorning.first?.end, 90)
    }

    func testUnparseableRowsAreSkippedNotCrashed() {
        XCTAssertTrue(parse("").isEmpty)
        XCTAssertTrue(parse("1N - BSCS 1-1N - TBA").isEmpty)
        XCTAssertTrue(parse("no times here at all").isEmpty)
    }
}
