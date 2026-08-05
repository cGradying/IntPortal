import AppKit
import SwiftUI

struct CalendarView: View {
    @ObservedObject var controller: PortalController
    @ObservedObject var preferences: Preferences
    let credentials: Credentials
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.canvasWash.ignoresSafeArea()

            // Having a schedule is what decides the screen, not the session
            // state: a cached week beats a spinner, and beats an error too.
            if controller.sessions.isEmpty {
                startupState
            } else {
                VStack(spacing: 0) {
                    WeekGrid(sessions: controller.sessions, preferences: preferences)
                    StatusFooter(
                        lastUpdated: controller.lastUpdated,
                        refreshError: controller.refreshError,
                        onRetry: retry
                    )
                }
            }
        }
        .task {
            if controller.status == .idle {
                controller.signIn(with: credentials)
            }
        }
    }

    /// Only ever seen on a first run, or after signing out — any later failure
    /// lands in the footer instead.
    @ViewBuilder
    private var startupState: some View {
        switch controller.status {
        case .idle, .loggingIn:
            ProgressView("Signing in…")

        case .failed(let message):
            ContentUnavailableView {
                Label("Can't reach your schedule", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again", action: retry)
                    .buttonStyle(.glassProminent)
                    .tint(palette.accent)
            }

        case .success:
            ContentUnavailableView(
                "No classes found",
                systemImage: "calendar",
                description: Text("The SIS didn't list any classes for this term.")
            )
        }
    }

    private func retry() {
        controller.signIn(with: credentials)
    }
}

// MARK: - Week grid

private struct WeekGrid: View {
    let sessions: [ClassSession]
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette

    private let gutter: CGFloat = 56
    private let headerHeight: CGFloat = 34
    private let hourHeight: CGFloat = 60
    /// Shared by the header and the grid so day labels line up with columns.
    private let columnInset: CGFloat = 12

    /// Axis padded to whole hours around the real class range, so the grid
    /// isn't a mostly-empty 24-hour column.
    private var axis: (start: Int, end: Int) {
        let starts = sessions.map(\.start)
        let ends = sessions.map(\.end)
        guard let first = starts.min(), let last = ends.max() else { return (7 * 60, 21 * 60) }
        return ((first / 60) * 60, Int(ceil(Double(last) / 60)) * 60)
    }

    private var hours: [Int] {
        stride(from: axis.start, through: axis.end, by: 60).map { $0 }
    }

    var body: some View {
        let span = CGFloat(max(axis.end - axis.start, 60))
        let bodyHeight = span / 60 * hourHeight

        // One clock for the whole grid: the same minute positions the now-line
        // and decides which blocks have already finished.
        TimelineView(.periodic(from: NowLine.nextMinute, by: 60)) { context in
            let now = context.date
            let today = Weekday.on(now)
            let minutes = NowLine.minutes(of: now)

            ZStack(alignment: .top) {
                scrollingBody(span: span, height: bodyHeight, today: today, minutes: minutes)
                header(today: today)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// Floats over the grid rather than sitting above it, so hours pass
    /// underneath the glass instead of colliding with a hard edge.
    private func header(today: Weekday) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(Weekday.allCases) { day in
                Text(day.short)
                    .font(Theme.Typo.dayName)
                    .foregroundStyle(day == today ? palette.accent : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(palette.accent.opacity(day == today ? 0.16 : 0))
                    )
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(day == today ? "\(day.short), today" : day.short)
            }
        }
        .frame(height: headerHeight)
        // Matches the scrolling body's trailing inset exactly. Padding the
        // header's leading edge instead would shift every label off its
        // column by that amount.
        .padding(.trailing, columnInset)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func scrollingBody(span: CGFloat, height: CGFloat, today: Weekday, minutes: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels(now: minutes)
                        .frame(width: gutter)

                    ZStack(alignment: .topLeading) {
                        hourLines(height: height)

                        HStack(spacing: 5) {
                            ForEach(Weekday.allCases) { day in
                                dayColumn(day, span: span, height: height,
                                          today: today, minutes: minutes)
                            }
                        }
                    }
                    .frame(height: height)
                }
                .overlay(alignment: .topLeading) {
                    NowLine(minutes: minutes, axisStart: axis.start,
                            span: span, height: height, gutter: gutter)
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, 12)
                .padding(.trailing, columnInset)
            }
            .onAppear {
                // Open on the current hour rather than at 7am. No animation:
                // an initial position should just be the position.
                guard let target = hours.last(where: { $0 <= minutes }) else { return }
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    /// The now-lozenge lives in this same gutter, so any hour label it would
    /// land on top of gets out of the way. The lozenge already says the time.
    private func hourLabels(now: Int) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { hour in
                Text(ClassSession.format(hour))
                    .font(Theme.Typo.gutter)
                    .foregroundStyle(.tertiary)
                    .opacity(abs(hour - now) < 20 ? 0 : 1)
                    .frame(height: hourHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.trailing, 8)
    }

    private func hourLines(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { hour in
                Rectangle()
                    .fill(palette.gridLine)
                    .frame(height: 1)
                    .frame(height: hourHeight, alignment: .top)
                    .id(hour)
            }
        }
        .frame(height: height, alignment: .top)
    }

    private func dayColumn(_ day: Weekday, span: CGFloat, height: CGFloat,
                           today: Weekday, minutes: Int) -> some View {
        GeometryReader { proxy in
            ForEach(sessions.filter { $0.day == day }) { session in
                SessionBlock(
                    session: session,
                    isPast: isPast(session, today: today, minutes: minutes),
                    preferences: preferences
                )
                    .frame(
                        width: proxy.size.width,
                        height: max(CGFloat(session.duration) / span * height, 26)
                    )
                    .offset(y: CGFloat(session.start - axis.start) / span * height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    /// The week reads Monday-first, and so does `Weekday`, so an earlier
    /// raw value is an earlier day of this same week.
    private func isPast(_ session: ClassSession, today: Weekday, minutes: Int) -> Bool {
        session.day.rawValue < today.rawValue
            || (session.day == today && session.end <= minutes)
    }
}

// MARK: - Blocks

private struct SessionBlock: View {
    let session: ClassSession
    let isPast: Bool
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @State private var showingDetail = false

    private var status: SessionStatus { preferences.status(for: session) }
    private var color: Color { preferences.color(for: session.subjectCode, in: palette) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.subjectCode)
                .font(Theme.Typo.blockCode)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 3) {
                if status != .regular {
                    Image(systemName: status.symbol)
                        .font(.system(size: 8))
                }
                Text(status == .vacant ? "Vacant" : session.timeLabel)
                    .font(Theme.Typo.blockTime)
            }
            .opacity(0.85)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Opaque on purpose. Glass belongs to the chrome; the blocks are the
        // content, and per-subject color has to survive being looked at.
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        // A vacant class keeps its outline so the slot still reads as spoken
        // for — it just stops looking like something you have to attend.
        .overlay {
            if status == .vacant {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .foregroundStyle(status == .vacant ? AnyShapeStyle(color) : AnyShapeStyle(.white))
        .shadow(color: .black.opacity(status == .vacant ? 0 : 0.18), radius: 1.5, y: 1)
        .opacity(isPast ? 0.45 : 1)
        .onTapGesture { showingDetail = true }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isPast ? "Already finished" : "Show details")
        .accessibilityAddTraits(.isButton)
        .popover(isPresented: $showingDetail) { detail }
    }

    private var fill: Color {
        status == .vacant ? color.opacity(0.14) : color
    }

    private var accessibilityLabel: String {
        let state = status == .regular ? "" : ", \(status.label)"
        return "\(session.subjectCode), \(session.description), \(session.timeLabel)\(state)"
    }

    @ViewBuilder
    private var contextMenu: some View {
        Picker("Status", selection: statusBinding) {
            ForEach(SessionStatus.allCases) { option in
                Label(option.label, systemImage: option.symbol).tag(option)
            }
        }
        .pickerStyle(.inline)

        Divider()

        // A real ColorPicker can't live in a menu, so this hands off to the
        // popover, which has one.
        Button("Change Color…") { showingDetail = true }
        Button("Reset Color") { preferences.resetColor(for: session.subjectCode) }
            .disabled(!preferences.hasCustomColor(for: session.subjectCode))
    }

    /// Opening the panel takes key window, which dismisses the popover — so
    /// capture what the callback needs instead of reading it back from a view
    /// that's already gone.
    private func presentColorPanel() {
        let preferences = preferences
        let subjectCode = session.subjectCode

        ColorPanelController.shared.present(current: color, near: NSEvent.mouseLocation) { picked in
            preferences.setColor(picked, for: subjectCode)
        }
    }

    private var statusBinding: Binding<SessionStatus> {
        Binding(
            get: { status },
            set: { preferences.setStatus($0, for: session) }
        )
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.subjectCode)
                    .font(Theme.Typo.detailTitle)
                Text(session.description)
                    .font(Theme.Typo.detailBody)
                Text("\(session.day.short)  \(session.timeLabel)")
                    .font(Theme.Typo.detailMeta)
                    .foregroundStyle(.secondary)
                if !session.faculty.isEmpty {
                    Text(session.faculty)
                        .font(Theme.Typo.detailBody)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Picker("Status", selection: statusBinding) {
                ForEach(SessionStatus.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            // Swatches inline rather than only a `ColorPicker`: the system
            // color panel opens as its own floating window somewhere else on
            // screen, which is a long way to go to recolor a block. The
            // picker stays for a genuinely custom color.
            HStack(spacing: 6) {
                ForEach(Array(palette.subjectColors.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        preferences.setColor(swatch, for: session.subjectCode)
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary, lineWidth: 2)
                                    .opacity(swatch.hex == color.hex ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Use this color")
                }

                Button(action: presentColorPanel) {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        ))
                        .frame(width: 20, height: 20)
                        .overlay { Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .help("Custom color…")

                Spacer()

                Button("Reset") { preferences.resetColor(for: session.subjectCode) }
                    .buttonStyle(.link)
                    .disabled(!preferences.hasCustomColor(for: session.subjectCode))
            }

            Text("Color applies to every \(session.subjectCode) block; status is just this meeting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .tint(palette.accent)
    }
}

// MARK: - Footer

/// Where a failed refresh goes now that it no longer gets to take the screen.
private struct StatusFooter: View {
    let lastUpdated: Date?
    let refreshError: String?
    let onRetry: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            if let refreshError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(refreshError)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(refreshError)
            }

            Text(staleness)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Button(refreshError == nil ? "Refresh" : "Try again", action: onRetry)
                .buttonStyle(.glass)
                .tint(palette.accent)
                .controlSize(.small)
        }
        .font(Theme.Typo.footer)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var staleness: String {
        guard let lastUpdated else { return "Never updated" }
        // Under a minute reads as "in 0 seconds" through the relative style,
        // which is worse than saying it plainly.
        guard Date().timeIntervalSince(lastUpdated) >= 60 else { return "Updated just now" }
        return "Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
    }
}
