import XCTest
@testable import PUPSISPortal

/// Term identity, history merging, and units — the logic behind the GPA trend.
/// Fixtures use fake terms and subjects only, never a real transcript.
final class GradeHistoryTests: XCTestCase {
    private func subject(_ code: String, units: String, grade: String) -> [String: String] {
        [
            "subjectCode": code, "description": "Test Subject", "faculty": "SANTOS, JUAN",
            "unit": units, "sectionCode": "1", "finalGrade": grade, "gradeStatus": "",
        ]
    }

    private func report(sy: String?, sem: String?, _ rows: [[String: String]]) -> GradeReport {
        GradeReport(
            lastUpdated: Date(timeIntervalSince1970: 1_754_400_000),
            subjects: GradesParser.parse(rows),
            summary: [:],
            schoolYear: sy,
            semester: sem
        )
    }

    // MARK: Term ordering

    func testTermOrderSortsByYearThenSemester() {
        let terms = [
            report(sy: "2025-2026", sem: "Summer", []),
            report(sy: "2024-2025", sem: "2nd Semester", []),
            report(sy: "2025-2026", sem: "1st Semester", []),
            report(sy: "2024-2025", sem: "1st Semester", []),
        ]
        let sorted = terms.sorted { $0.termOrder < $1.termOrder }.map(\.termLabel)

        XCTAssertEqual(sorted, [
            "1st Sem 2024-2025",
            "2nd Sem 2024-2025",
            "1st Sem 2025-2026",
            "Summer 2025-2026",
        ])
    }

    func testSummerRanksAfterBothRegularSemesters() {
        XCTAssertGreaterThan(
            GradeReport.semesterRank("Summer"),
            GradeReport.semesterRank("2nd Semester")
        )
    }

    // MARK: History merge

    func testMergeReplacesTheSameTermAndKeepsOthers() {
        let history = [
            report(sy: "2024-2025", sem: "1st Semester", [subject("A", units: "3", grade: "2.00")]),
        ]
        // Same term re-scraped, now with a better grade.
        let updated = report(sy: "2024-2025", sem: "1st Semester",
                             [subject("A", units: "3", grade: "1.00")])

        let merged = GradesStore.merged(updated, into: history)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.computedGPA, 1.00)
    }

    func testMergeKeepsResultSortedOldestFirst() {
        var history: [GradeReport] = []
        // Insert out of order.
        history = GradesStore.merged(report(sy: "2025-2026", sem: "1st Semester", []), into: history)
        history = GradesStore.merged(report(sy: "2024-2025", sem: "1st Semester", []), into: history)

        XCTAssertEqual(history.map(\.termLabel), ["1st Sem 2024-2025", "1st Sem 2025-2026"])
    }

    // MARK: Units

    func testCompletedUnitsCountsPostedSubjectsOnly() {
        let term = report(sy: "2024-2025", sem: "1st Semester", [
            subject("A", units: "3", grade: "1.00"),   // posted
            subject("B", units: "2", grade: ""),        // unposted — excluded
            subject("C", units: "3", grade: "INC"),     // non-numeric — excluded
        ])

        XCTAssertEqual(term.completedUnits, 3, accuracy: 0.0001)
    }

    // MARK: Back-compat

    /// A report cached before term fields existed must still decode — as an
    /// untagged term with a non-crashing label — not fail the whole history load.
    func testLegacyReportWithoutTermFieldsStillDecodes() throws {
        let legacy = """
        {"lastUpdated": 1754400000, "subjects": [], "summary": {}}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GradeReport.self, from: legacy)

        XCTAssertNil(decoded.schoolYear)
        XCTAssertNil(decoded.semester)
        XCTAssertFalse(decoded.termLabel.isEmpty)
    }
}
