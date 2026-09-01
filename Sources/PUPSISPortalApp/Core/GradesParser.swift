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

    /// Which term this snapshot is, read from the grades page's School Year /
    /// Semester dropdowns. Optional so a report cached before history existed
    /// (no term fields) still decodes — it just reads as an untagged term.
    let schoolYear: String?
    let semester: String?

    init(
        lastUpdated: Date,
        subjects: [SubjectGrade],
        summary: [String: String],
        schoolYear: String? = nil,
        semester: String? = nil
    ) {
        self.lastUpdated = lastUpdated
        self.subjects = subjects
        self.summary = summary
        self.schoolYear = schoolYear
        self.semester = semester
    }

    /// Our own weighted GPA over the posted subjects — the number SIS shows one
    /// term at a time but never breaks down. `nil` when nothing is posted yet,
    /// which reads as "no GPA" rather than a misleading 0.00.
    var computedGPA: Double? { GradesParser.gpa(of: subjects) }

    var hasPostedGrades: Bool { subjects.contains { $0.isPosted } }

    /// Units the student has actually earned this term — posted subjects only,
    /// so unposted and INC/DRP don't inflate the count.
    var completedUnits: Double {
        subjects.filter(\.isPosted).reduce(0) { $0 + $1.units }
    }

    /// A short, stable label for the term. Falls back to the update date for a
    /// legacy untagged snapshot so it still reads as *something*.
    var termLabel: String {
        switch (schoolYear, semester) {
        case let (sy?, sem?): "\(GradeReport.shortSemester(sem)) \(sy)"
        case let (sy?, nil): sy
        case let (nil, sem?): sem
        case (nil, nil): lastUpdated.formatted(.dateTime.year().month())
        }
    }

    /// Chronological sort key: `startYear * 10 + semester rank`, so terms line
    /// up oldest-first on the trend regardless of scrape order.
    /// ponytail: string heuristic on the dropdown label — fine for PUP's fixed
    /// term names ("2025-2026", "1st Semester", "Summer"); revisit only if the
    /// site changes how it prints them.
    var termOrder: Int {
        let year = schoolYear.flatMap { GradeReport.startYear(of: $0) } ?? 0
        return year * 10 + GradeReport.semesterRank(semester)
    }

    static func startYear(of schoolYear: String) -> Int? {
        // "2025-2026" → 2025; take the first run of digits.
        let digits = schoolYear.prefix { $0.isNumber }
        return Int(digits)
    }

    static func semesterRank(_ semester: String?) -> Int {
        guard let s = semester?.lowercased() else { return 0 }
        if s.contains("1st") || s.contains("first") { return 1 }
        if s.contains("2nd") || s.contains("second") { return 2 }
        // Summer / midyear sits after both regular semesters.
        if s.contains("summer") || s.contains("mid") { return 3 }
        return 0
    }

    static func shortSemester(_ semester: String) -> String {
        let s = semester.lowercased()
        if s.contains("1st") || s.contains("first") { return "1st Sem" }
        if s.contains("2nd") || s.contains("second") { return "2nd Sem" }
        if s.contains("summer") || s.contains("mid") { return "Summer" }
        return semester
    }
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

    /// The units-weighted average grade needed on every unposted subject to
    /// land the term at `target` overall — algebra on the same weighting
    /// `gpa(of:)` already does, solved for the unknown side instead of read
    /// off both. `nil` when there's nothing left to post (already fully
    /// posted) or nothing carries units at all — there's no equation to
    /// solve either way.
    ///
    /// PUP grades run 1.00 (best) to 5.00 (fail); the caller decides what to
    /// do with a result outside that range (already locked in below/above
    /// target regardless of what's left) rather than this clamping it away.
    static func neededAverage(for subjects: [SubjectGrade], target: Double) -> Double? {
        let posted = subjects.compactMap { subject -> (grade: Double, units: Double)? in
            guard let grade = subject.numericGrade, subject.units > 0 else { return nil }
            return (grade, subject.units)
        }
        let remainingUnits = subjects
            .filter { !$0.isPosted && $0.units > 0 }
            .reduce(0) { $0 + $1.units }
        guard remainingUnits > 0 else { return nil }

        let postedUnits = posted.reduce(0) { $0 + $1.units }
        let postedWeighted = posted.reduce(0) { $0 + $1.grade * $1.units }
        let totalUnits = postedUnits + remainingUnits

        let needed = (target * totalUnits - postedWeighted) / remainingUnits
        return (needed * 100).rounded() / 100
    }
}
