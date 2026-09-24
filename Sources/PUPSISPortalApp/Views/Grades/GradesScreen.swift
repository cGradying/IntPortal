import SwiftUI

/// The Grades screen. For most of a semester the grade cells are empty — the
/// school hasn't posted yet — so the not-yet-posted state is the one this
/// view is built around, not an afterthought.
///
/// Beyond the current term it also reads `controller.gradeHistory`: a GPA
/// trend across terms and units-completed progress, the two things SIS shows
/// one term at a time but never puts together.
struct GradesScreen: View {
    @ObservedObject var controller: PortalController
    @ObservedObject var preferences: Preferences
    /// Off for snapshots: `ImageRenderer` can't draw a `ScrollView`.
    var scrolls = true
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    /// Which term's subject list is on screen, keyed by `termLabel`. `nil` =
    /// the current term.
    @State private var selectedTerm: String?
    /// Target GPA for "What do I need" — per-term, not persisted, so a stray
    /// "3.00" typed while browsing a past term doesn't survive to the next
    /// launch or leak into a different term's card.
    @State private var targetGPA: Double = 2.0

    private var report: GradeReport? { controller.grades }

    /// Every term we can show: the backfilled history plus the current term.
    /// The current term is kept even without posted grades (so it never gets
    /// folded into `gradeHistory`) — otherwise the picker would list only
    /// past terms and the on-screen term couldn't be selected back to.
    private var allTerms: [GradeReport] {
        var terms = controller.gradeHistory
        if let report, !terms.contains(where: { $0.termLabel == report.termLabel }) {
            terms.append(report)
        }
        return terms
    }

    /// The term whose subjects are shown: the picker's choice, else the
    /// current term, else the most recent one we have.
    private var displayedReport: GradeReport? {
        if let selectedTerm, let match = allTerms.first(where: { $0.termLabel == selectedTerm }) {
            return match
        }
        return report ?? allTerms.last
    }

    var body: some View {
        VStack(spacing: 0) {
            if scrolls {
                ScrollView { scrollableContent }.scrollIndicators(.hidden)
            } else {
                scrollableContent
            }
            if let shown = displayedReport { footer(shown) }
        }
        .background(palette.roles.ground)
        .task { if controller.grades == nil { await controller.loadGrades() } }
        .onAppear {
            // Default the pickers to the on-screen term so they show a
            // selection instead of a blank menu.
            if selectedTerm == nil { selectedTerm = (report ?? allTerms.last)?.termLabel }
        }
    }

    private var scrollableContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                termSheet.frame(maxWidth: .infinity)
                trendSheet.frame(minWidth: 280, maxWidth: .infinity)
            }
            if let shown = displayedReport {
                if shown.subjects.isEmpty {
                    emptyTermSheet(shown)
                } else {
                    GradesTable(report: shown, preferences: preferences)
                    progressSheet(shown)
                }
            } else {
                noDataSheet
            }
            historyControl
        }
        .padding(Spacing.xxl)
    }

    // MARK: Term

    private var termSheet: some View {
        Sheet(label: "Term", meta: "as listed on the SIS grades page") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                termFilters
                if let shown = displayedReport, !shown.subjects.isEmpty {
                    gpaHero(shown)
                } else if let shown = displayedReport {
                    Text("No grades yet")
                        .font(typography.display(size: 16))
                        .foregroundStyle(palette.roles.ink3)
                        .accessibilityHidden(shown.subjects.isEmpty)
                }
            }
            .padding(Spacing.lg)
        }
    }

    @ViewBuilder
    private func gpaHero(_ shown: GradeReport) -> some View {
        let posted = shown.subjects.filter(\.isPosted)
        let total = shown.subjects.count
        let termUnits = shown.subjects.reduce(0.0) { $0 + $1.units }
        let allPassed = total > 0 && posted.count == total
            && posted.allSatisfy { $0.gradeStatus.localizedCaseInsensitiveContains("pass") }

        HStack(alignment: .center, spacing: Spacing.lg) {
            Text(shown.computedGPA.map { String(format: "%.2f", $0) } ?? "—")
                .font(typography.display(size: 56, weight: .bold))
                .foregroundStyle(shown.computedGPA == nil ? palette.roles.ink3 : palette.roles.ink)
                .fixedSize()

            VStack(alignment: .leading, spacing: 6) {
                Text("GPA, \(posted.count) of \(total) subject\(total == 1 ? "" : "s") posted, \(unitLabel(termUnits)).")
                    .font(typography.reading(size: 14))
                    .foregroundStyle(palette.roles.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if allPassed {
                    Text("All passed")
                        .font(typography.display(size: 12))
                        .foregroundStyle(palette.roles.good)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(palette.roles.good.opacity(0.14), in: PixelNotch())
                }
            }
        }
    }

    /// The School year / Semester selects. Falls back to a single Term menu
    /// for a legacy cached report that predates those fields.
    @ViewBuilder
    private var termFilters: some View {
        let years = schoolYears
        if !years.isEmpty {
            HStack(spacing: Spacing.md) {
                fieldPicker(label: "School year", selection: schoolYearBinding, options: years) { $0 }
                fieldPicker(
                    label: "Semester", selection: semesterBinding, options: semesters(in: schoolYearBinding.wrappedValue),
                    display: GradeReport.shortSemester
                )
            }
        } else if allTerms.count > 1 {
            Picker("Term", selection: $selectedTerm) {
                ForEach(allTerms.reversed(), id: \.termLabel) { term in
                    Text(term.termLabel).tag(Optional(term.termLabel))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func fieldPicker(
        label: String, selection: Binding<String>, options: [String], display: @escaping (String) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(typography.display(size: 11))
                .tracking(0.5)
                .foregroundStyle(palette.roles.ink3)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in Text(display(option)).tag(option) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(palette.roles.sheet, in: PixelNotch())
            .overlay(PixelNotch().strokeBorder(palette.roles.line2, lineWidth: 2))
        }
    }

    private var schoolYears: [String] {
        Set(allTerms.compactMap(\.schoolYear))
            .sorted { (GradeReport.startYear(of: $0) ?? 0) > (GradeReport.startYear(of: $1) ?? 0) }
    }

    private func semesters(in schoolYear: String) -> [String] {
        Set(allTerms.filter { $0.schoolYear == schoolYear }.compactMap(\.semester))
            .sorted { GradeReport.semesterRank($0) < GradeReport.semesterRank($1) }
    }

    private var schoolYearBinding: Binding<String> {
        Binding(
            get: { displayedReport?.schoolYear ?? schoolYears.first ?? "" },
            set: { newYear in
                let currentSemester = displayedReport?.semester
                let candidates = allTerms.filter { $0.schoolYear == newYear }
                selectedTerm = (candidates.first { $0.semester == currentSemester } ?? candidates.last)?.termLabel
            }
        )
    }

    private var semesterBinding: Binding<String> {
        Binding(
            get: { displayedReport?.semester ?? semesters(in: schoolYearBinding.wrappedValue).first ?? "" },
            set: { newSemester in
                let year = displayedReport?.schoolYear
                selectedTerm = allTerms.first { $0.schoolYear == year && $0.semester == newSemester }?.termLabel
            }
        )
    }

    // MARK: Trend

    private var trendSheet: some View {
        let trendTerms = GPATrendChart.trendTerms(from: allTerms)
        return Sheet(label: "GPA trend", meta: "lower is better, 1.00 is highest") {
            Group {
                if trendTerms.count >= 2 {
                    GPATrendChart(terms: trendTerms).padding(Spacing.lg)
                } else {
                    Text("The trend needs at least two posted terms.")
                        .font(typography.reading(size: 14))
                        .foregroundStyle(palette.roles.ink3)
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .padding(Spacing.lg)
                }
            }
        }
    }

    // MARK: Progress (units completed + what do I need)

    private func progressSheet(_ shown: GradeReport) -> some View {
        Sheet(label: "Progress", meta: "units and what's left") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                unitsBlock
                if shown.subjects.contains(where: { !$0.isPosted && $0.units > 0 }) {
                    Rectangle().fill(palette.roles.line).frame(height: 1)
                    neededGradeBlock(shown)
                }
            }
            .padding(Spacing.lg)
        }
    }

    private var unitsBlock: some View {
        // Cumulative across every term we have. ponytail: no retake dedup —
        // a repeated subject counts twice; revisit if that ever matters.
        let completed = allTerms.reduce(0.0) { $0 + $1.completedUnits }
        let total = preferences.programTotalUnits

        return VStack(alignment: .leading, spacing: 8) {
            Text("Units completed")
                .font(typography.display(size: 13))
                .foregroundStyle(palette.roles.ink2)

            if total > 0 {
                Text("\(bareUnitCount(completed)) / \(total)")
                    .font(typography.numeric(size: 18, weight: .semibold))
                    .foregroundStyle(palette.roles.ink)
                GeometryReader { geo in
                    let ratio = min(completed / Double(total), 1)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(palette.roles.sunk)
                        Rectangle().fill(palette.subjectColors[0]).frame(width: geo.size.width * ratio)
                    }
                }
                .frame(height: 8)
            } else {
                Text(bareUnitCount(completed))
                    .font(typography.numeric(size: 18, weight: .semibold))
                    .foregroundStyle(palette.roles.ink)
                Text("Set your program's total units in Settings to see progress.")
                    .font(typography.reading(size: 13))
                    .foregroundStyle(palette.roles.ink3)
            }
        }
    }

    private func bareUnitCount(_ units: Double) -> String {
        units.rounded() == units ? String(Int(units)) : String(format: "%.1f", units)
    }

    @ViewBuilder
    private func neededGradeBlock(_ report: GradeReport) -> some View {
        let needed = GradesParser.neededAverage(for: report.subjects, target: targetGPA)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What do I need")
                    .font(typography.display(size: 13))
                    .foregroundStyle(palette.roles.ink2)
                Spacer()
                Stepper(value: $targetGPA, in: 1...5, step: 0.25) {
                    Text("Target: \(String(format: "%.2f", targetGPA))")
                        .font(typography.numeric(size: 13))
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
                .font(typography.reading(size: 16, weight: .semibold))
                .foregroundStyle(impossible ? palette.roles.good : (alreadyLocked ? palette.roles.bad : palette.roles.ink))
            }

            Text("Remember: lower is better on PUP's 1.00\u{2013}5.00 scale. This only weights units, not any exam/lab breakdown \u{2014} SIS doesn't publish one.")
                .font(typography.reading(size: 13))
                .foregroundStyle(palette.roles.ink3)
        }
    }

    // MARK: Chrome

    private func emptyTermSheet(_ shown: GradeReport) -> some View {
        Sheet(label: "Grades") {
            emptyState(
                title: "No grades yet",
                description: "\(shown.termLabel) is still running. IntPortal checks the SIS each time you refresh and fills this in when your professors post."
            ) {
                if let posted = allTerms.last(where: { !$0.subjects.isEmpty }) {
                    Button("Show a posted term") { selectedTerm = posted.termLabel }
                        .buttonStyle(.pixelSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var noDataSheet: some View {
        Sheet(label: "Grades") {
            if let error = controller.gradesError {
                emptyState(title: "Can't reach your grades", description: error) {
                    Button("Try again") { Task { await controller.loadGrades() } }
                        .buttonStyle(.pixelPrimary)
                }
            } else {
                emptyState(
                    title: "No grades yet",
                    description: "Grades appear here once you're enrolled and the school posts them."
                ) { EmptyView() }
            }
        }
    }

    /// A dithered pixel badge over a title, one line and an optional action —
    /// the shape every "nothing here" state in this screen takes.
    @ViewBuilder
    private func emptyState<Action: View>(
        title: String, description: String, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 10) {
            DitherFill(color: palette.roles.ink3, cell: 3, ramp: .flat(0.55))
                .frame(width: 96, height: 56)
                .clipShape(PixelNotch())
            Text(title)
                .font(typography.display(size: 20, weight: .bold))
                .foregroundStyle(palette.roles.ink)
            Text(description)
                .font(typography.reading(size: 14))
                .foregroundStyle(palette.roles.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            action()
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var historyControl: some View {
        if controller.isLoadingHistory {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading past terms…")
                    .font(typography.reading(size: 13))
                    .foregroundStyle(palette.roles.ink3)
            }
        } else if controller.gradeHistory.count < 2 {
            Button("Load past terms") { Task { await controller.loadGradeHistory() } }
                .buttonStyle(.pixelSecondary)
        }
    }

    private func footer(_ shown: GradeReport) -> some View {
        HStack(spacing: Spacing.sm) {
            if let error = controller.gradesError {
                Text(error)
                    .font(typography.reading(size: 13))
                    .foregroundStyle(palette.roles.bad)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(error)
            }
            Text("Updated \(shown.lastUpdated.formatted(.relative(presentation: .named)))")
                .font(typography.reading(size: 13))
                .foregroundStyle(palette.roles.ink3)
            Spacer(minLength: 12)
            Button("Refresh") { Task { await controller.loadGrades() } }
                .buttonStyle(.pixelSecondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(palette.roles.sheet)
        .overlay(alignment: .top) { Rectangle().fill(palette.roles.line).frame(height: 1) }
    }
}
