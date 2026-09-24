import XCTest
@testable import PUPSISPortal

/// Renders the rebuilt Grades screen with demo data. Fixtures use the same
/// fake subjects `Demo.grades` does, never a real transcript.
@MainActor
final class GradesSnapshotTests: XCTestCase {
    private func makeController(grades: GradeReport?, history: [GradeReport] = []) -> PortalController {
        let controller = PortalController(defaults: UserDefaults(suiteName: "GradesSnapshotTests-\(UUID().uuidString)")!)
        controller.grades = grades
        controller.gradeHistory = history
        return controller
    }

    private func makePreferences(programTotalUnits: Int = 144) -> Preferences {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "GradesSnapshotTests-\(UUID().uuidString)")!)
        preferences.programTotalUnits = programTotalUnits
        return preferences
    }

    /// A past term with a different GPA, so the trend has two points to plot
    /// and "Load past terms" still shows (history count stays under two).
    private static let pastTerm = GradeReport(
        lastUpdated: Date(timeIntervalSince1970: 1_722_400_000),
        subjects: [
            ("GEED 001", "Understanding the Self", 3.0, "1.75"),
            ("GEED 002", "Readings in Philippine History", 3.0, "1.75"),
        ].map {
            SubjectGrade(subjectCode: $0.0, description: $0.1, faculty: "Prof. Sample", units: $0.2,
                         sectionCode: "", finalGrade: $0.3, gradeStatus: "Passed")
        },
        summary: ["GPA": "1.75"],
        schoolYear: "2024-2025",
        semester: "First Semester"
    )

    func testGradesScreenRendersInBothRegistrarPalettes() throws {
        let controller = makeController(grades: Demo.grades, history: [Self.pastTerm])
        let preferences = makePreferences()

        let light = try Snapshot.render(
            GradesScreen(controller: controller, preferences: preferences, scrolls: false),
            name: "grades-light", palette: .registrar, scheme: .light
        )
        let dark = try Snapshot.render(
            GradesScreen(controller: controller, preferences: preferences, scrolls: false),
            name: "grades-dark", palette: .registrarNight, scheme: .dark
        )
        XCTAssertEqual(light.size, dark.size)
    }

    /// A subject the school hasn't posted yet must read "Pending", not blank
    /// or a stray zero.
    func testAPendingSubjectReadsPending() throws {
        var subjects = Demo.grades.subjects
        subjects.append(SubjectGrade(
            subjectCode: "NSTP 002", description: "Civic Welfare Training Service 2", faculty: "Prof. Sample",
            units: 3, sectionCode: "", finalGrade: "", gradeStatus: ""
        ))
        let report = GradeReport(
            lastUpdated: Demo.grades.lastUpdated, subjects: subjects, summary: Demo.grades.summary,
            schoolYear: Demo.grades.schoolYear, semester: Demo.grades.semester
        )
        let controller = makeController(grades: report, history: [Self.pastTerm])

        let image = try Snapshot.render(
            GradesScreen(controller: controller, preferences: makePreferences(), scrolls: false),
            name: "grades-pending", palette: .registrar, scheme: .light
        )
        XCTAssertGreaterThan(image.size.height, 200)
    }

    /// A term with no rows yet (the running semester) shows the dithered
    /// empty state rather than an empty table.
    func testAnEmptyTermShowsTheDitheredEmptyState() throws {
        let empty = GradeReport(
            lastUpdated: .init(timeIntervalSince1970: 1_758_700_000), subjects: [], summary: [:],
            schoolYear: "2026-2027", semester: "First Semester"
        )
        let controller = makeController(grades: empty, history: [Self.pastTerm])

        let image = try Snapshot.render(
            GradesScreen(controller: controller, preferences: makePreferences(), scrolls: false),
            name: "grades-empty", palette: .registrar, scheme: .light
        )
        XCTAssertGreaterThan(image.size.height, 200)
    }

    // MARK: GPA trend VoiceOver summary

    private func report(gpa: Double, sy: String, sem: String) -> GradeReport {
        GradeReport(
            lastUpdated: .init(), subjects: [
                SubjectGrade(subjectCode: "TEST 001", description: "Test", faculty: "", units: 1,
                             sectionCode: "", finalGrade: String(format: "%.2f", gpa), gradeStatus: "Passed"),
            ], summary: [:], schoolYear: sy, semester: sem
        )
    }

    /// Lower is better on PUP's scale, so a numeric drop between terms is the
    /// improving direction and must read "up from".
    func testVoiceOverSummaryAnnouncesAnImprovingTermAsUp() {
        let terms = [
            report(gpa: 2.00, sy: "2024-2025", sem: "1st Semester"),
            report(gpa: 1.50, sy: "2024-2025", sem: "2nd Semester"),
        ]
        let summary = GPATrendChart.accessibilitySummary(for: terms)
        XCTAssertTrue(summary.contains("Latest 1.50"), summary)
        XCTAssertTrue(summary.contains("up from 2.00"), summary)
    }

    /// A numeric rise between terms is the falling direction and must read
    /// "down from".
    func testVoiceOverSummaryAnnouncesAFallingTermAsDown() {
        let terms = [
            report(gpa: 1.50, sy: "2024-2025", sem: "1st Semester"),
            report(gpa: 2.00, sy: "2024-2025", sem: "2nd Semester"),
        ]
        let summary = GPATrendChart.accessibilitySummary(for: terms)
        XCTAssertTrue(summary.contains("Latest 2.00"), summary)
        XCTAssertTrue(summary.contains("down from 1.50"), summary)
    }
}
