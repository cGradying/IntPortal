import SwiftUI

/// The Grades sheet: one row per subject and a GPA footer. Column widths are
/// fixed so a row of five subjects lines up like an SIS record sheet rather
/// than reflowing per row.
struct GradesTable: View {
    let report: GradeReport
    let preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    /// Flips true on first appear so rows land in reading order once, not on
    /// every re-render (e.g. a picker change).
    @State private var appeared = false

    private static let subjectWidth: CGFloat = 108
    private static let unitsWidth: CGFloat = 60
    private static let gradeWidth: CGFloat = 88
    private static let remarksWidth: CGFloat = 92

    var body: some View {
        Sheet(label: "Grades") {
            VStack(spacing: 0) {
                header
                ForEach(Array(report.subjects.enumerated()), id: \.element.id) { index, subject in
                    row(subject, index: index)
                    if index != report.subjects.count - 1 {
                        Rectangle().fill(palette.roles.line).frame(height: 1)
                    }
                }
                footer
            }
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        let roles = palette.roles
        return HStack(spacing: Spacing.md) {
            columnHeader("Subject").frame(width: Self.subjectWidth, alignment: .leading)
            columnHeader("Description").frame(maxWidth: .infinity, alignment: .leading)
            columnHeader("Units").frame(width: Self.unitsWidth, alignment: .trailing)
            columnHeader("Final grade").frame(width: Self.gradeWidth, alignment: .trailing)
            columnHeader("Remarks").frame(width: Self.remarksWidth, alignment: .leading)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(roles.sunk)
        .overlay(alignment: .bottom) { Rectangle().fill(roles.line2).frame(height: 2) }
    }

    private func columnHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(typography.display(size: 12))
            .tracking(0.6)
            .foregroundStyle(palette.roles.ink3)
    }

    private func row(_ subject: SubjectGrade, index: Int) -> some View {
        let roles = palette.roles
        return HStack(spacing: Spacing.md) {
            Text(subject.subjectCode)
                .font(typography.display(size: 15))
                .foregroundStyle(preferences.color(for: subject.subjectCode, in: palette))
                .frame(width: Self.subjectWidth, alignment: .leading)
            Text(subject.description)
                .font(typography.reading(size: 14))
                .foregroundStyle(roles.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(unitLabel(subject.units))
                .font(typography.numeric(size: 13))
                .foregroundStyle(roles.ink2)
                .frame(width: Self.unitsWidth, alignment: .trailing)
            finalGrade(subject).frame(width: Self.gradeWidth, alignment: .trailing)
            RemarksPill(subject: subject).frame(width: Self.remarksWidth, alignment: .leading)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm + 2)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(
            Motion.arrival(reduced: reduceMotion)?.delay(Motion.stagger(index, reduced: reduceMotion)),
            value: appeared
        )
        .accessibilityElement(children: .combine)
    }

    /// Empty = not posted → "Pending". A non-empty non-numeric mark (INC,
    /// DRP) shows as itself, since that's not the same as missing.
    @ViewBuilder
    private func finalGrade(_ subject: SubjectGrade) -> some View {
        if subject.isPosted {
            Text(subject.finalGrade)
                .font(typography.numeric(size: 16, weight: .semibold))
                .foregroundStyle(palette.roles.ink)
        } else {
            Text(subject.finalGrade.isEmpty ? "Pending" : subject.finalGrade)
                .font(typography.numeric(size: 13))
                .foregroundStyle(palette.roles.ink3)
        }
    }

    private var footer: some View {
        let roles = palette.roles
        let termUnits = report.subjects.reduce(0.0) { $0 + $1.units }
        return HStack(spacing: Spacing.md) {
            Text("GPA")
                .font(typography.display(size: 13))
                .foregroundStyle(roles.ink2)
                .frame(width: Self.subjectWidth, alignment: .leading)
            Spacer(minLength: 0)
            Text(unitLabel(termUnits))
                .font(typography.numeric(size: 14, weight: .semibold))
                .foregroundStyle(roles.ink)
                .frame(width: Self.unitsWidth, alignment: .trailing)
            Text(report.computedGPA.map { String(format: "%.2f", $0) } ?? "—")
                .font(typography.numeric(size: 16, weight: .semibold))
                .foregroundStyle(roles.ink)
                .frame(width: Self.gradeWidth, alignment: .trailing)
            Color.clear.frame(width: Self.remarksWidth)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm + 2)
        .background(roles.sunk)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GPA \(report.computedGPA.map { String(format: "%.2f", $0) } ?? "not available"), \(unitLabel(termUnits))")
    }
}

/// A subject's remarks, as SIS prints them (Passed, Failed, INC, DRP…),
/// tinted only when the remark itself is a pass/fail — everything else
/// (unposted, INC, DRP) stays neutral ink rather than guessing a verdict.
private struct RemarksPill: View {
    let subject: SubjectGrade
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        if let text = displayText {
            Text(text)
                .font(typography.display(size: 12))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(tint.opacity(0.14), in: PixelNotch())
        }
    }

    private var displayText: String? {
        if !subject.gradeStatus.isEmpty { return subject.gradeStatus }
        return subject.isPosted ? "Posted" : nil
    }

    private var tint: Color {
        let roles = palette.roles
        let status = subject.gradeStatus.lowercased()
        if status.contains("pass") { return roles.good }
        if status.contains("fail") { return roles.bad }
        return roles.ink2
    }
}

/// Drops a trailing ".0" so "3 units" doesn't read as "3.0 units".
func unitLabel(_ units: Double) -> String {
    let whole = units.rounded() == units
    let value = whole ? String(Int(units)) : String(units)
    return "\(value) unit\(units == 1 ? "" : "s")"
}
