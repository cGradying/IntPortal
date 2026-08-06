import Foundation

/// One subject's grade for a term. `finalGrade` is empty until the school
/// posts it — which, for most of a semester, is the normal state.
struct SubjectGrade: Identifiable, Equatable, Codable {
    let subjectCode: String
    let description: String
    let faculty: String
    let units: Double
    let sectionCode: String
    /// As printed: "1.00", "" (not posted yet), or a non-numeric mark like
    /// "INC" / "DRP". Kept as a string because those last three all live here.
    let finalGrade: String
    let gradeStatus: String

    /// Section code disambiguates the same subject taken twice; falling back to
    /// the code keeps the id stable when a section isn't listed.
    var id: String { sectionCode.isEmpty ? subjectCode : "\(subjectCode)-\(sectionCode)" }

    /// The numeric value only when the grade is posted *and* numeric. PUP grades
    /// run 1.00 (best) to 5.00 (fail); "INC", "DRP", and a blank cell all return
    /// `nil` so they never get counted as a zero — which would be the obvious,
    /// wrong way to average them.
    var numericGrade: Double? {
        Double(finalGrade.trimmingCharacters(in: .whitespaces))
    }

    var isPosted: Bool { numericGrade != nil }
}

/// Everything the Grades page yields: the per-subject rows plus the free-form
/// summary block (Admission Status, Scholastic Status, GPA as SIS prints it).
struct GradeReport: Codable, Equatable {
    let lastUpdated: Date
    let subjects: [SubjectGrade]
    /// The `<dl>` summary as label → value. Stored raw so an unrecognised key
    /// on the live page still round-trips instead of being dropped.
    let summary: [String: String]

    /// Our own weighted GPA over the posted subjects — the number SIS shows one
    /// term at a time but never breaks down. `nil` when nothing is posted yet,
    /// which reads as "no GPA" rather than a misleading 0.00.
    var computedGPA: Double? { GradesParser.gpa(of: subjects) }

    var hasPostedGrades: Bool { subjects.contains { $0.isPosted } }
}

/// Turns scraped grade rows into typed values, and computes the GPA.
enum GradesParser {
    static func parse(_ rows: [[String: String]]) -> [SubjectGrade] {
        rows.compactMap(parse)
    }

    /// A row with no subject code is a spacer or a totals line, not a subject —
    /// skipped, never crashed on.
    private static func parse(_ row: [String: String]) -> SubjectGrade? {
        let code = (row["subjectCode"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return nil }

        return SubjectGrade(
            subjectCode: code,
            description: (row["description"] ?? "").trimmingCharacters(in: .whitespaces),
            faculty: (row["faculty"] ?? "").trimmingCharacters(in: .whitespaces),
            units: Double((row["unit"] ?? "").trimmingCharacters(in: .whitespaces)) ?? 0,
            sectionCode: (row["sectionCode"] ?? "").trimmingCharacters(in: .whitespaces),
            finalGrade: (row["finalGrade"] ?? "").trimmingCharacters(in: .whitespaces),
            gradeStatus: (row["gradeStatus"] ?? "").trimmingCharacters(in: .whitespaces)
        )
    }

    /// Units-weighted average of the posted numeric grades. Unposted and
    /// non-numeric subjects (INC, DRP) are excluded entirely — they don't drag
    /// the average toward zero, and a subject with zero listed units can't
    /// weight anything.
    static func gpa(of subjects: [SubjectGrade]) -> Double? {
        let posted = subjects.compactMap { subject -> (grade: Double, units: Double)? in
            guard let grade = subject.numericGrade, subject.units > 0 else { return nil }
            return (grade, subject.units)
        }

        let totalUnits = posted.reduce(0) { $0 + $1.units }
        guard totalUnits > 0 else { return nil }

        let weighted = posted.reduce(0) { $0 + $1.grade * $1.units }
        return (weighted / totalUnits * 100).rounded() / 100
    }
}
