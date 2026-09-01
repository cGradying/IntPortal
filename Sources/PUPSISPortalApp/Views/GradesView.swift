import Charts
import SwiftUI

/// The Grades screen. For most of a semester the grade cells are empty — the
/// school hasn't posted yet — so the not-yet-posted state is the one this view
/// is built around, not an afterthought.
///
/// Beyond the current term it also reads `controller.gradeHistory`: a GPA trend
/// across terms and units-completed progress, the two things SIS shows one term
/// at a time but never puts together.
struct GradesView: View {
    @ObservedObject var controller: PortalController
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which term's subject list is on screen. `nil` = the current term.
    @State private var selectedTerm: String?
    /// Flipped true on first appear so the subject rows animate in once.
    @State private var appeared = false

    private var report: GradeReport? { controller.grades }

    /// Every term we can show: the backfilled history plus the current term.
    /// The current term is kept even when it has no posted grades (so it never
    /// gets folded into `gradeHistory`) — otherwise the picker would list only
    /// past terms and the on-screen term couldn't be selected back to.
    private var allTerms: [GradeReport] {
        var terms = controller.gradeHistory
        if let report, !terms.contains(where: { $0.termLabel == report.termLabel }) {
            terms.append(report)
        }
        return terms
    }

    /// Terms with a real GPA — the only ones a trend line should plot.
    private var trendTerms: [GradeReport] {
        allTerms.filter { $0.computedGPA != nil }
    }

    /// The term whose subjects are shown: the picker's choice, else the current
    /// term, else the most recent one we have.
    private var displayedReport: GradeReport? {
        if let selectedTerm, let match = allTerms.first(where: { $0.termLabel == selectedTerm }) {
            return match
        }
        return report ?? allTerms.last
    }

    var body: some View {
        ZStack {
            palette.canvasWash.ignoresSafeArea()

            if let shown = displayedReport, !shown.subjects.isEmpty {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            if trendTerms.count >= 2 { trendCard }
                            unitsCard
                            if allTerms.count > 1 { termPicker }
                            summaryCard(shown)
                            if shown.subjects.contains(where: { !$0.isPosted && $0.units > 0 }) {
                                neededGradeCard(shown)
                            }
                            subjectList(shown)
                            historyControl
                        }
                        .padding(20)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    footer(shown)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Grades")
        .task { if controller.grades == nil { await controller.loadGrades() } }
        .onAppear {
            appeared = true
            // Default the picker to the on-screen term so it shows a selection
            // instead of a blank menu (tags are all non-nil term labels).
            if selectedTerm == nil { selectedTerm = (report ?? allTerms.last)?.termLabel }
        }
    }

    // MARK: Trend

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GPA trend")
                .font(typography.detailMeta)
                .foregroundStyle(.secondary)

            Chart(trendTerms, id: \.termLabel) { term in
                LineMark(
                    x: .value("Term", term.termLabel),
                    y: .value("GPA", term.computedGPA ?? 0)
                )
                .foregroundStyle(palette.accent)
                PointMark(
                    x: .value("Term", term.termLabel),
                    y: .value("GPA", term.computedGPA ?? 0)
                )
                .foregroundStyle(palette.accent)
            }
            // PUP grades run 1.00 (best) to 5.00 (worst). Fix the domain to the
            // full scale, flipped so the better GPA sits at the top where
            // "up = good" reads correctly, and label every whole mark.
            .chartYScale(domain: [5.0, 1.0])
            .chartYAxis {
                AxisMarks(values: [1.0, 2.0, 3.0, 4.0, 5.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let gpa = value.as(Double.self) {
                            Text(String(format: "%.2f", gpa))
                        }
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel(trendAccessibilitySummary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }

    /// A spoken summary for the chart: the latest GPA and which way it moved.
    private var trendAccessibilitySummary: String {
        let posted = trendTerms.compactMap { term in term.computedGPA.map { (term.termLabel, $0) } }
        guard let latest = posted.last else { return "GPA trend" }

        let base = "GPA trend across \(posted.count) terms. Latest \(String(format: "%.2f", latest.1)) in \(latest.0)."
        guard posted.count >= 2 else { return base }

        let previous = posted[posted.count - 2].1
        // Lower is better on the PUP scale, so a drop in the number is an
        // improvement — say it in plain terms, not in the raw direction.
        let direction: String
        if latest.1 < previous { direction = "up from" }
        else if latest.1 > previous { direction = "down from" }
        else { direction = "unchanged from" }
        return base + " \(direction) \(String(format: "%.2f", previous))."
    }

    private var unitsCard: some View {
        // Cumulative across every term we have. ponytail: no retake dedup — a
        // repeated subject counts twice; revisit if that ever matters.
        let completed = allTerms.reduce(0.0) { $0 + $1.completedUnits }
        let total = preferences.programTotalUnits

        return VStack(alignment: .leading, spacing: 8) {
            Text("Units completed")
                .font(typography.detailMeta)
                .foregroundStyle(.secondary)

            if total > 0 {
                Text("\(unitString(completed)) / \(total)")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                ProgressView(value: min(completed / Double(total), 1))
                    .tint(palette.accent)
            } else {
                Text(unitString(completed))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                Text("Set your program's total units in Settings to see progress.")
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }

    private var termPicker: some View {
        Picker("Term", selection: $selectedTerm) {
            ForEach(allTerms.reversed(), id: \.termLabel) { term in
                Text(term.termLabel).tag(Optional(term.termLabel))
            }
        }
        .pickerStyle(.menu)
        .tint(palette.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var historyControl: some View {
        if controller.isLoadingHistory {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading past terms…")
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else if controller.gradeHistory.count < 2 {
            Button("Load past terms") { Task { await controller.loadGradeHistory() } }
                .glassButton()
                .tint(palette.accent)
                .controlSize(.small)
        }
    }

    private func unitString(_ units: Double) -> String {
        units.rounded() == units ? String(Int(units)) : String(format: "%.1f", units)
    }

    // MARK: What do I need

    /// Target GPA is per-term, not persisted — a stray "3.00" typed while
    /// browsing a past term shouldn't survive to the next launch or leak
    /// into a different term's card.
    @State private var targetGPA: Double = 2.0

    @ViewBuilder
    private func neededGradeCard(_ report: GradeReport) -> some View {
        let needed = GradesParser.neededAverage(for: report.subjects, target: targetGPA)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What do I need")
                    .font(typography.detailMeta)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $targetGPA, in: 1...5, step: 0.25) {
                    Text("Target: \(String(format: "%.2f", targetGPA))")
                        .font(typography.footer)
                }
                .fixedSize()
            }

            if let needed {
                let impossible = needed < 1.0
                let alreadyLocked = needed > 5.0
                Group {
                    if impossible {
                        Text("Already better than \(String(format: "%.2f", targetGPA)) is possible on what's posted \u{2014} you can't average below 1.00.")
                    } else if alreadyLocked {
                        Text("Even a 5.00 on what's left can't reach \(String(format: "%.2f", targetGPA)) anymore.")
                    } else {
                        Text("Average **\(String(format: "%.2f", needed))** on your unposted subjects to land at \(String(format: "%.2f", targetGPA)).")
                    }
                }
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(impossible ? palette.accent : (alreadyLocked ? .red : .primary))
            }

            Text("Remember: lower is better on PUP's 1.00\u{2013}5.00 scale. This only weights units, not any exam/lab breakdown \u{2014} SIS doesn't publish one.")
                .font(typography.footer)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }

    // MARK: Summary

    @ViewBuilder
    private func summaryCard(_ report: GradeReport) -> some View {
        let posted = report.subjects.filter(\.isPosted).count
        let total = report.subjects.count

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GPA")
                    .font(typography.detailMeta)
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
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            summaryStatuses(report.summary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
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
                            .font(typography.detailMeta)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(typography.footer.weight(.medium))
                    }
                }
            }
        }
    }

    // MARK: Subjects

    private func subjectList(_ report: GradeReport) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(report.subjects.enumerated()), id: \.element.id) { index, subject in
                GradeRow(
                    subject: subject,
                    color: preferences.color(for: subject.subjectCode, in: palette)
                )
                // Rows land in reading order on open, the same arrival the
                // week grid and Today screen use. Reduce Motion → instant.
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .animation(
                    Motion.arrival(reduced: reduceMotion)?
                        .delay(Motion.stagger(index, reduced: reduceMotion)),
                    value: appeared
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
                    .glassProminentButton()
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
                .glassButton()
                .tint(palette.accent)
                .controlSize(.small)
        }
        .font(typography.footer)
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

    @Environment(\.typography) private var typography

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.subjectCode)
                    .font(typography.blockCode)
                Text(subject.description)
                    .font(typography.footer)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if subject.units > 0 {
                Text(unitLabel)
                    .font(typography.detailMeta)
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
                .font(typography.footer.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: .capsule)
        }
    }
}
