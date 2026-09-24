import SwiftUI

/// The Grades sheet: one row per subject and a GPA footer, laid out in a
/// `Grid` so every column sizes to its widest cell automatically — a subject
/// code never truncates, and only Description (the one column with room to
/// give) wraps instead of growing the sheet sideways.
///
/// `Grid` applies a modifier you put on a `GridRow` to each of that row's
/// cells independently, not to one unified row frame — a divider is built
/// explicitly as its own `GridRow` spanning all columns rather than relied
/// on as a whole-row overlay.
///
/// Only Description's cells ever take `maxWidth: .infinity`. Every other
/// column must stay content-sized: `Grid` shares leftover width among *all*
/// columns that have any flexible cell in them, so making a header label
/// flexible too would cut Description's share and reopen the truncation
/// this table exists to prevent.
struct GradesTable: View {
    let report: GradeReport
    let preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    /// Flips true on first appear so rows land in reading order once, not on
    /// every re-render (e.g. a picker change).
    @State private var appeared = false

    private static let columnCount = 5

    var body: some View {
        let roles = palette.roles
        Sheet(label: "Grades") {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                header
                divider(roles.line2, height: 2)
                ForEach(Array(report.subjects.enumerated()), id: \.element.id) { index, subject in
                    row(subject, index: index)
                    if index != report.subjects.count - 1 { divider(roles.line, height: 1) }
                }
                footer
            }
            // The Grid's own edge inset; each cell adds the rest of
            // Spacing.lg itself so the gap between cells reads right too.
            .padding(.horizontal, Spacing.lg - Spacing.sm)
        }
        .onAppear { appeared = true }
    }

    private func divider(_ color: Color, height: CGFloat) -> some View {
        GridRow { Rectangle().fill(color).frame(height: height).gridCellColumns(Self.columnCount) }
    }

    private var header: some View {
        GridRow {
            headerCell("Subject", alignment: .leading)
            headerCell("Description", alignment: .leading)
            headerCell("Units", alignment: .trailing).gridColumnAlignment(.trailing)
            headerCell("Final grade", alignment: .trailing).gridColumnAlignment(.trailing)
            headerCell("Remarks", alignment: .leading)
        }
    }

    private func headerCell(_ text: String, alignment: Alignment) -> some View {
        // No `maxWidth: .infinity` here — see the type's doc comment. The
        // sunk fill stays sized to the label itself rather than the
        // column's full resolved width, which is the trade this table
        // makes for guaranteeing Description never truncates.
        Text(text.uppercased())
            .font(typography.display(size: 12))
            .tracking(0.6)
            .foregroundStyle(palette.roles.ink3)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(palette.roles.sunk)
    }

    private func row(_ subject: SubjectGrade, index: Int) -> some View {
        let roles = palette.roles
        let readout = "\(subject.subjectCode), \(subject.description), \(unitLabel(subject.units)), \(gradeReadout(subject)), \(remarksReadout(subject))"

        return GridRow {
            // No frame, no lineLimit: a code is never allowed to truncate,
            // so it always reports and gets its own natural width — Grid
            // then sizes the whole column to the widest one in the term.
            Text(subject.subjectCode)
                .font(typography.display(size: 15))
                .foregroundStyle(preferences.color(for: subject.subjectCode, in: palette))
                .fixedSize()
                .rowCell(appeared: appeared, index: index, reduceMotion: reduceMotion)
                .accessibilityLabel(readout)

            Text(subject.description)
                .font(typography.reading(size: 14))
                .foregroundStyle(roles.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowCell(appeared: appeared, index: index, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            Text(unitLabel(subject.units))
                .font(typography.numeric(size: 13))
                .foregroundStyle(roles.ink2)
                .rowCell(appeared: appeared, index: index, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            finalGrade(subject)
                .rowCell(appeared: appeared, index: index, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            RemarksPill(subject: subject)
                .rowCell(appeared: appeared, index: index, reduceMotion: reduceMotion)
                .accessibilityHidden(true)
        }
    }

    private func gradeReadout(_ subject: SubjectGrade) -> String {
        subject.isPosted ? subject.finalGrade : (subject.finalGrade.isEmpty ? "Pending" : subject.finalGrade)
    }

    private func remarksReadout(_ subject: SubjectGrade) -> String {
        if !subject.gradeStatus.isEmpty { return subject.gradeStatus }
        return subject.isPosted ? "Posted" : "not yet posted"
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
        let gpaText = report.computedGPA.map { String(format: "%.2f", $0) } ?? "—"

        // Same trade as the header cells: no `maxWidth: .infinity`, so the
        // sunk fill sits tight around each value instead of competing with
        // Description for leftover column width.
        return GridRow {
            Text("GPA")
                .font(typography.display(size: 13))
                .foregroundStyle(roles.ink2)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm + 2)
                .background(roles.sunk)
                .gridCellColumns(2)
                .accessibilityLabel("GPA \(gpaText), \(unitLabel(termUnits))")

            Text(unitLabel(termUnits))
                .font(typography.numeric(size: 14, weight: .semibold))
                .foregroundStyle(roles.ink)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm + 2)
                .background(roles.sunk)
                .accessibilityHidden(true)

            Text(gpaText)
                .font(typography.numeric(size: 16, weight: .semibold))
                .foregroundStyle(roles.ink)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm + 2)
                .background(roles.sunk)
                .accessibilityHidden(true)

            Color.clear
                .frame(width: 1)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm + 2)
                .background(roles.sunk)
                .accessibilityHidden(true)
        }
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

/// A data row's per-cell padding and arrival animation — every cell in a
/// row gets this individually, since `Grid` distributes a `GridRow`
/// modifier to each cell rather than wrapping the row as one view.
private extension View {
    func rowCell(appeared: Bool, index: Int, reduceMotion: Bool) -> some View {
        padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm + 2)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .animation(
                Motion.arrival(reduced: reduceMotion)?.delay(Motion.stagger(index, reduced: reduceMotion)),
                value: appeared
            )
    }
}

/// Drops a trailing ".0" so "3 units" doesn't read as "3.0 units".
func unitLabel(_ units: Double) -> String {
    let whole = units.rounded() == units
    let value = whole ? String(Int(units)) : String(units)
    return "\(value) unit\(units == 1 ? "" : "s")"
}
