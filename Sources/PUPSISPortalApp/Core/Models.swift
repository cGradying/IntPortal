import Foundation

struct ScheduleEntry: Identifiable {
    let id = UUID()
    let subjectCode: String
    let description: String
    let lec: String
    let lab: String
    let unit: String
    let schedule: String

    init?(row: [String: String]) {
        guard let subjectCode = row["Subject Code"], !subjectCode.isEmpty else { return nil }
        self.subjectCode = subjectCode
        description = row["Description"] ?? ""
        lec = row["Lec"] ?? ""
        lab = row["Lab"] ?? ""
        unit = row["Unit"] ?? ""
        schedule = row["Schedule"] ?? ""
    }
}

struct GradeEntry: Identifiable {
    let id = UUID()
    let subjectCode: String
    let description: String
    let facultyName: String
    let units: String
    let sectCode: String
    let finalGrade: String
    let gradeStatus: String

    init?(row: [String: String]) {
        guard let subjectCode = row["Subject Code"], !subjectCode.isEmpty else { return nil }
        self.subjectCode = subjectCode
        description = row["Description"] ?? ""
        facultyName = row["Faculty Name"] ?? ""
        units = row["Units"] ?? ""
        sectCode = row["Sect Code"] ?? ""
        finalGrade = row["Final Grade"] ?? ""
        gradeStatus = row["Grade Status"] ?? ""
    }
}

/// The SIS renders these as separate one-row `<dl>` blocks above the grades table.
struct AcademicSummary {
    var admissionStatus = ""
    var scholasticStatus = ""
    var courseDescription = ""
    var gpa = ""

    init(fields: [String: String] = [:]) {
        admissionStatus = fields["Admission Status"] ?? ""
        scholasticStatus = fields["Scholastic Status"] ?? ""
        courseDescription = fields["Course Code & Description"] ?? ""
        gpa = fields.first(where: { $0.key.hasPrefix("GPA") })?.value ?? ""
    }
}
