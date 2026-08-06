import SwiftUI

/// The Grades screen. For most of a semester the grade cells are empty — the
/// school hasn't posted yet — so the not-yet-posted state is the one this view
/// is built around, not an afterthought.
struct GradesView: View {
    @ObservedObject var controller: PortalController
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette

    private var report: GradeReport? { controller.grades }

    var body: some View {
        ZStack {
            palette.canvasWash.ignoresSafeArea()

            if let report, !report.subjects.isEmpty {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard(report)
                            subjectList(report)
                        }
                        .padding(20)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    footer(report)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Grades")
        .task { if controller.grades == nil { await controller.loadGrades() } }
    }

    // MARK: Summary

    @ViewBuilder
    private func summaryCard(_ report: GradeReport) -> some View {
        let posted = report.subjects.filter(\.isPosted).count
        let total = report.subjects.count

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GPA")
                    .font(Theme.Typo.detailMeta)
                    .foregroundStyle(.secondary)

                if let gpa = report.computedGPA {
                    Text(String(format: "%.2f", gpa))
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(posted == 0
                     ? "No grades posted yet"
                     : "\(posted) of \(total) subject\(total == 1 ? "" : "s") posted")
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            summaryStatuses(report.summary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// Whatever the page's `<dl>` listed, shown as-is. Skips the GPA line — the
    /// number above is ours, computed and weighted, not the page's flat print.
    @ViewBuilder
    private func summaryStatuses(_ summary: [String: String]) -> some View {
        let rows = summary
            .filter { !$0.key.lowercased().contains("gpa") && !$0.value.isEmpty }
            .sorted { $0.key < $1.key }

        if !rows.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(rows, id: \.key) { key, value in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(key)
                            .font(Theme.Typo.detailMeta)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(Theme.Typo.footer.weight(.medium))
                    }
                }
            }
        }
    }

    // MARK: Subjects

    private func subjectList(_ report: GradeReport) -> some View {
        VStack(spacing: 8) {
            ForEach(report.subjects) { subject in
                GradeRow(
                    subject: subject,
                    color: preferences.color(for: subject.subjectCode, in: palette)
                )
            }
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private var emptyState: some View {
        if let error = controller.gradesError, controller.grades == nil {
            ContentUnavailableView {
                Label("Can't reach your grades", systemImage: "graduationcap")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await controller.loadGrades() } }
                    .buttonStyle(.glassProminent)
                    .tint(palette.accent)
            }
        } else {
            ContentUnavailableView(
                "No grades yet",
                systemImage: "graduationcap",
                description: Text("Grades appear here once you're enrolled and the school posts them.")
            )
        }
    }

    private func footer(_ report: GradeReport) -> some View {
        HStack(spacing: 8) {
            if let error = controller.gradesError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(1).truncationMode(.tail).help(error)
            }

            Text("Updated \(report.lastUpdated.formatted(.relative(presentation: .named)))")
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Button("Refresh") { Task { await controller.loadGrades() } }
                .buttonStyle(.glass)
                .tint(palette.accent)
                .controlSize(.small)
        }
        .font(Theme.Typo.footer)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// One subject line: colour, code, description, units, and a grade badge that
/// reads "Pending" until posted rather than showing a blank or a zero.
private struct GradeRow: View {
    let subject: SubjectGrade
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.subjectCode)
                    .font(Theme.Typo.blockCode)
                Text(subject.description)
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if subject.units > 0 {
                Text(unitLabel)
                    .font(Theme.Typo.detailMeta)
                    .foregroundStyle(.secondary)
            }

            gradeBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private var unitLabel: String {
        // Drop a trailing ".0" so "3 units" doesn't read as "3.0 units".
        let whole = subject.units.rounded() == subject.units
        let value = whole ? String(Int(subject.units)) : String(subject.units)
        return "\(value) unit\(subject.units == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var gradeBadge: some View {
        if subject.isPosted {
            Text(subject.finalGrade)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
                .frame(minWidth: 52)
                .padding(.vertical, 4)
                .background(color.opacity(0.14), in: .capsule)
        } else {
            // Empty cell = not posted; a non-empty non-numeric mark (INC, DRP)
            // shows as itself so it's clearly not just missing.
            Text(subject.finalGrade.isEmpty ? "Pending" : subject.finalGrade)
                .font(Theme.Typo.footer.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: .capsule)
        }
    }
}
