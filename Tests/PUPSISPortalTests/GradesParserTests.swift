import XCTest
@testable import PUPSISPortal

/// Fixtures use the same fake subjects the rest of the suite does — never a
/// real transcript, name, or student number.
final class GradesParserTests: XCTestCase {
    private func row(_ code: String, units: String, grade: String,
                     status: String = "", section: String = "1") -> [String: String] {
        [
            "subjectCode": code,
            "description": "Test Subject",
            "faculty": "SANTOS, JUAN",
            "unit": units,
            "sectionCode": section,
            "finalGrade": grade,
            "gradeStatus": status,
        ]
    }

    func testParsesEveryFieldOfARow() {
        let subject = GradesParser.parse([row("COMP 20073", units: "3", grade: "1.75", status: "Passed")]).first

        XCTAssertEqual(subject?.subjectCode, "COMP 20073")
        XCTAssertEqual(subject?.units, 3)
        XCTAssertEqual(subject?.finalGrade, "1.75")
        XCTAssertEqual(subject?.gradeStatus, "Passed")
        XCTAssertTrue(subject?.isPosted == true)
    }

    /// A blank grade cell is the normal state for most of a semester, not a
    /// parse failure — the subject still lists, just unposted.
    func testAnUnpostedGradeStillListsTheSubject() {
        let subject = GradesParser.parse([row("COMP 20073", units: "3", grade: "")]).first

        XCTAssertEqual(subject?.subjectCode, "COMP 20073")
        XCTAssertFalse(subject?.isPosted == true)
        XCTAssertNil(subject?.numericGrade)
    }

    func testRowsWithNoSubjectCodeAreSkippedNotCrashed() {
        let rows = [
            row("", units: "0", grade: ""),          // spacer / totals line
            row("COMP 20073", units: "3", grade: "1.00"),
        ]
        let subjects = GradesParser.parse(rows)

        XCTAssertEqual(subjects.count, 1)
        XCTAssertEqual(subjects.first?.subjectCode, "COMP 20073")
    }

    // MARK: GPA

    /// With nothing posted the GPA is absent, not 0.00 — a zero would read as a
    /// perfect-fail average that never happened.
    func testAllUnpostedYieldsNoGPA() {
        let subjects = GradesParser.parse([
            row("COMP 20073", units: "3", grade: ""),
            row("GEED 005", units: "3", grade: ""),
        ])

        XCTAssertNil(GradesParser.gpa(of: subjects))
        XCTAssertFalse(GradeReport(lastUpdated: .init(), subjects: subjects, summary: [:]).hasPostedGrades)
    }

    /// A mix weights only the posted subjects; the unposted one contributes
    /// neither grade nor units.
    func testGPAWeightsOnlyThePostedSubjects() throws {
        let subjects = GradesParser.parse([
            row("COMP 20073", units: "3", grade: "1.00"),
            row("GEED 005", units: "1", grade: "2.00"),
            row("PATHFIT 1", units: "2", grade: ""),      // unposted — ignored
        ])

        // (1.00·3 + 2.00·1) / (3 + 1) = 1.25
        XCTAssertEqual(try XCTUnwrap(GradesParser.gpa(of: subjects)), 1.25, accuracy: 0.0001)
    }

    /// A non-numeric mark (INC, DRP) is excluded from the average but must
    /// still appear in the list.
    func testNonNumericMarksAreExcludedFromGPAButStillListed() throws {
        let subjects = GradesParser.parse([
            row("COMP 20073", units: "3", grade: "1.50"),
            row("GEED 005", units: "3", grade: "INC"),
            row("PATHFIT 1", units: "2", grade: "DRP"),
        ])

        XCTAssertEqual(subjects.count, 3)
        // Only COMP 20073 counts, so its own grade is the average.
        XCTAssertEqual(try XCTUnwrap(GradesParser.gpa(of: subjects)), 1.50, accuracy: 0.0001)
    }

    /// A posted grade on a zero-unit subject can't weight anything, so it must
    /// not divide by zero or skew the average.
    func testZeroUnitSubjectsDoNotBreakTheAverage() throws {
        let subjects = GradesParser.parse([
            row("COMP 20073", units: "3", grade: "2.00"),
            row("NSTP 001", units: "0", grade: "1.00"),
        ])

        XCTAssertEqual(try XCTUnwrap(GradesParser.gpa(of: subjects)), 2.00, accuracy: 0.0001)
    }

    /// Section code disambiguates a subject taken twice; ids must stay distinct.
    func testSameSubjectDifferentSectionsGetDistinctIDs() {
        let subjects = GradesParser.parse([
            row("COMP 20073", units: "3", grade: "1.00", section: "1"),
            row("COMP 20073", units: "3", grade: "2.00", section: "2"),
        ])

        XCTAssertEqual(Set(subjects.map(\.id)).count, 2)
    }

    func testTheStoreRoundTripsAReport() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GradesStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("grades.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let report = GradeReport(
            lastUpdated: Date(timeIntervalSince1970: 1_754_400_000),
            subjects: GradesParser.parse([row("COMP 20073", units: "3", grade: "1.25")]),
            summary: ["Scholastic Status": "Regular"]
        )
        GradesStore.save(report, to: url)

        let loaded = GradesStore.load(from: url)
        XCTAssertEqual(loaded?.subjects, report.subjects)
        XCTAssertEqual(loaded?.summary, report.summary)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }
}
