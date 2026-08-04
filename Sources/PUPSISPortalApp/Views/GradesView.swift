import SwiftUI

struct GradesView: View {
    let entries: [GradeEntry]
    let summary: AcademicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !summary.gpa.isEmpty {
                HStack(spacing: 24) {
                    summaryItem("Admission", summary.admissionStatus)
                    summaryItem("Scholastic", summary.scholasticStatus)
                    summaryItem("GPA", summary.gpa)
                }
                .padding()
                Divider()
            }

            if entries.isEmpty {
                EmptyStateView(title: "No grades loaded yet", systemImage: "chart.bar")
            } else {
                Table(entries) {
                    TableColumn("Code", value: \.subjectCode)
                    TableColumn("Description", value: \.description)
                    TableColumn("Faculty", value: \.facultyName)
                    TableColumn("Units", value: \.units)
                    TableColumn("Grade", value: \.finalGrade)
                    TableColumn("Status", value: \.gradeStatus)
                }
            }
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.headline)
                .foregroundStyle(Theme.accent)
        }
    }
}
