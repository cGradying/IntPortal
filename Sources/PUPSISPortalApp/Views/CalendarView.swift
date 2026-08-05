import AppKit
import SwiftUI

struct CalendarView: View {
    @ObservedObject var controller: PortalController
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    let credentials: Credentials
    @Environment(\.palette) private var palette

    /// Weeks away from the current one. Classes repeat, so browsing is only
    /// interesting once dated calendar events land in the grid — but the grid
    /// has to be dated before they can.
    @State private var weekOffset = 0
    @State private var scale: CalendarScale = .week
    @State private var newEvent: NewEventRequest?

    private var weekStart: Date {
        let thisWeek = Weekday.weekStart(containing: .now)
        return Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: thisWeek) ?? thisWeek
    }

    private var year: Int {
        Calendar.current.component(.year, from: weekStart)
    }

    /// Classes and calendar events end up in one list so the grid draws one
    /// kind of thing and overlap layout can see across both.
    private var blocks: [DayBlock] {
        controller.sessions.map(DayBlock.init) + calendar.events
    }

    var body: some View {
        ZStack {
            palette.canvasWash.ignoresSafeArea()

            // Having a schedule is what decides the screen, not the session
            // state: a cached week beats a spinner, and beats an error too.
            if controller.sessions.isEmpty {
                startupState
            } else {
                VStack(spacing: 0) {
                    switch scale {
                    case .week:
                        WeekGrid(blocks: blocks, weekStart: weekStart, preferences: preferences)
                    case .year:
                        YearView(year: year, selectedWeekStart: weekStart) { open($0) }
                    }

                    StatusFooter(
                        lastUpdated: controller.lastUpdated,
                        refreshError: controller.refreshError,
                        onRetry: retry
                    )
                }
            }
        }
        .navigationTitle(weekTitle)
        .toolbar { weekNavigation }
        .task {
            if controller.status == .idle {
                controller.signIn(with: credentials)
            }
        }
        // Reload whenever the week or the ticked calendars change.
        .task(id: reloadKey) {
            calendar.load(weekStart: weekStart, calendarIDs: preferences.visibleCalendarIDs)
        }
        // ...and when Calendar.app itself changes underneath us.
        .onReceive(NotificationCenter.default.publisher(for: .calendarStoreChanged)) { _ in
            calendar.load(weekStart: weekStart, calendarIDs: preferences.visibleCalendarIDs)
        }
        .sheet(item: $newEvent) { request in
            AddEventSheet(calendar: calendar, preferences: preferences, initialDate: request.date)
        }
    }

    /// `sheet(item:)` needs identity, and a plain `Date` has none — two
    /// requests for the same slot would be treated as the same sheet.
    private struct NewEventRequest: Identifiable {
        let id = UUID()
        let date: Date
    }

    /// Opens on today when the current week is showing, otherwise on the
    /// Monday of whatever week is being browsed.
    private func startNewEvent() {
        let today = Date.now
        let inThisWeek = Weekday.weekStart(containing: today) == weekStart
        newEvent = NewEventRequest(date: inThisWeek ? today : weekStart)
    }

    private var reloadKey: String {
        "\(weekStart.timeIntervalSince1970)-\(preferences.visibleCalendarIDs.sorted().joined())"
    }

    @ToolbarContentBuilder
    private var weekNavigation: some ToolbarContent {
        ToolbarItemGroup {
            Picker("View", selection: $scale) {
                ForEach(CalendarScale.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                step(-1)
            } label: {
                Label(scale == .week ? "Previous Week" : "Previous Year", systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("Today") { weekOffset = 0 }
                .disabled(weekOffset == 0)

            Button {
                step(1)
            } label: {
                Label(scale == .week ? "Next Week" : "Next Year", systemImage: "chevron.right")
            }
            .keyboardShortcut("]", modifiers: .command)

            Button(action: startNewEvent) {
                Label("New Event", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(calendar.access != .granted)
            .help(calendar.access == .granted
                  ? "Add an event to Calendar"
                  : "Connect Calendar in Settings first")
        }
    }

    /// The arrows move by whatever the current view shows, so they stay useful
    /// in the year view instead of nudging it a week at a time.
    private func step(_ direction: Int) {
        switch scale {
        case .week:
            weekOffset += direction
        case .year:
            let target = Calendar.current.date(byAdding: .year, value: direction, to: weekStart)
            if let target { open(target, switchToWeek: false) }
        }
    }

    /// Picking a date in the year view opens that week — the point of the year
    /// view is getting somewhere, not staying there.
    private func open(_ date: Date, switchToWeek: Bool = true) {
        let thisWeek = Weekday.weekStart(containing: .now)
        let target = Weekday.weekStart(containing: date)
        let days = Calendar.current.dateComponents([.day], from: thisWeek, to: target).day ?? 0

        weekOffset = days / 7
        if switchToWeek { scale = .week }
    }

    private var weekTitle: String {
        switch scale {
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "\(weekStart.formatted(short)) – \(end.formatted(short))"
        case .year:
            return String(year)
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
    let blocks: [DayBlock]
    let weekStart: Date
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette

    private let gutter: CGFloat = 56
    private let headerHeight: CGFloat = 44
    private let hourHeight: CGFloat = 60
    /// Shared by the header and the grid so day labels line up with columns.
    private let columnInset: CGFloat = 12

    private var axis: (start: Int, end: Int) {
        GridAxis.hours(covering: blocks)
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

            ZStack(alignment: .top) {
                scrollingBody(span: span, height: bodyHeight, now: now)
                header(now: now)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// Floats over the grid rather than sitting above it, so hours pass
    /// underneath the glass instead of colliding with a hard edge.
    private func header(now: Date) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(Weekday.allCases) { day in
                let isToday = isToday(day, now: now)

                VStack(spacing: 1) {
                    Text(day.short)
                        .font(Theme.Typo.dayName)
                    Text(dayNumber(day))
                        .font(Theme.Typo.gutter)
                        .opacity(0.8)
                }
                .foregroundStyle(isToday ? palette.accent : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.accent.opacity(isToday ? 0.16 : 0)))
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isToday ? "\(day.short) \(dayNumber(day)), today"
                                            : "\(day.short) \(dayNumber(day))")
            }
        }
        .frame(height: headerHeight)
        // Matches the scrolling body's trailing inset exactly. Padding the
        // header's leading edge instead would shift every label off its
        // column by that amount.
        .padding(.trailing, columnInset)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func scrollingBody(span: CGFloat, height: CGFloat, now: Date) -> some View {
        let nowMinutes = NowLine.minutes(of: now)

        return ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels(now: showsNowLine(now) ? nowMinutes : nil)
                        .frame(width: gutter)

                    ZStack(alignment: .topLeading) {
                        hourLines(height: height)

                        HStack(spacing: 5) {
                            ForEach(Weekday.allCases) { day in
                                dayColumn(day, span: span, height: height, now: now)
                            }
                        }
                    }
                    .frame(height: height)
                }
                .overlay(alignment: .topLeading) {
                    // Only the week that actually contains today gets a now-line.
                    if showsNowLine(now) {
                        NowLine(minutes: nowMinutes, axisStart: axis.start,
                                span: span, height: height, gutter: gutter)
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, 12)
                .padding(.trailing, columnInset)
            }
            .onAppear {
                // Open on the current hour rather than at 7am. No animation:
                // an initial position should just be the position.
                guard let target = hours.last(where: { $0 <= nowMinutes }) else { return }
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    /// The now-lozenge lives in this same gutter, so any hour label it would
    /// land on top of gets out of the way. The lozenge already says the time.
    private func hourLabels(now: Int?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { hour in
                Text(ClassSession.format(hour))
                    .font(Theme.Typo.gutter)
                    .foregroundStyle(.tertiary)
                    .opacity(now.map { abs(hour - $0) < 20 } == true ? 0 : 1)
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

    private func dayColumn(_ day: Weekday, span: CGFloat, height: CGFloat, now: Date) -> some View {
        let placements = BlockLayout.arrange(blocks.filter { $0.day == day })

        return GeometryReader { proxy in
            ForEach(placements) { placement in
                let width = proxy.size.width / CGFloat(placement.lanes)

                blockView(placement.block, isPast: isPast(placement.block, now: now))
                    .frame(
                        width: max(width - 2, 1),
                        height: max(CGFloat(placement.block.duration) / span * height, 26)
                    )
                    .offset(
                        x: width * CGFloat(placement.lane),
                        y: CGFloat(placement.block.start - axis.start) / span * height
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    @ViewBuilder
    private func blockView(_ block: DayBlock, isPast: Bool) -> some View {
        if let session = block.session {
            ClassBlock(session: session, isPast: isPast, preferences: preferences)
        } else {
            EventBlock(block: block, isPast: isPast)
        }
    }

    // MARK: Dates

    private func isToday(_ day: Weekday, now: Date) -> Bool {
        Calendar.current.isDate(day.date(inWeekStarting: weekStart), inSameDayAs: now)
    }

    private func showsNowLine(_ now: Date) -> Bool {
        Weekday.weekStart(containing: now) == weekStart
    }

    private func dayNumber(_ day: Weekday) -> String {
        String(Calendar.current.component(.day, from: day.date(inWeekStarting: weekStart)))
    }

    /// Compared against real dates rather than weekday order, so browsing to
    /// last week greys everything and next week greys nothing.
    private func isPast(_ block: DayBlock, now: Date) -> Bool {
        let date = block.day.date(inWeekStarting: weekStart)
        guard let end = Calendar.current.date(byAdding: .minute, value: block.end, to: date) else {
            return false
        }
        return end <= now
    }
}

// MARK: - Blocks

private struct ClassBlock: View {
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

/// A calendar event. Deliberately plainer than a class: it isn't the app's
/// data, so it gets no color or status controls.
private struct EventBlock: View {
    let block: DayBlock
    let isPast: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(Theme.Typo.blockCode)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(block.subtitle)
                .font(Theme.Typo.blockTime)
                .opacity(0.85)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.secondary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(palette.secondary)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .foregroundStyle(.primary)
        .opacity(isPast ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), \(block.subtitle)")
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
