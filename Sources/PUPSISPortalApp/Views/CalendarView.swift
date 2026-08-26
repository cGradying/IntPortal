import AppKit
import SwiftUI

/// The Schedule screen's shell: which week, which scale, what's selected, and
/// where the editor pops from. The grid itself lives in `WeekGrid`, and every
/// calendar mutation goes through `EventEditor` so undo has one hook.
struct CalendarView: View {
    @ObservedObject var controller: PortalController
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    let credentials: Credentials
    /// Week/scale/show-cancelled + the island's step/new-event intents. Lifted
    /// out so the floating nav island drives these instead of a toolbar.
    @ObservedObject var schedule: ScheduleModel
    /// Sparkle's delegate shim. `@ObservedObject`, not a plain `String?` —
    /// `updaterBridge` is its own `ObservableObject` nested inside `AppState`,
    /// so this view must observe it directly or a version becoming available
    /// while this screen is already on-screen wouldn't repaint the footer.
    @ObservedObject var updaterBridge: UpdaterBridge
    let onCheckForUpdates: () -> Void
    /// Settings is a sheet floating over this screen, not a replacement for
    /// it — `CalendarView` stays mounted underneath, so the scroll monitor
    /// needs telling explicitly not to move the schedule behind it.
    var settingsShowing: Bool = false

    @Environment(\.palette) private var palette

    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    @State private var selection: Set<String> = []
    @State private var editing: EditorRequest?
    /// Whether the visible grid/year scroll is pinned to its top edge — what
    /// gates the scroll-driven Week↔Year switch. Defaults true since both
    /// start there before their first layout pass reports in.
    @State private var atTop = true
    /// Set when an edit lands on a repeating event and the scope has to be
    /// asked for rather than assumed.
    @State private var pendingScope: ScopeQuestion?
    @StateObject private var editor: EventEditor
    /// Sidebar width captured at the start of a resize drag — same
    /// convention as `AgendaView`'s own `sidebarWidthAtDragStart`.
    @State private var sidebarWidthAtDragStart: Double?
    @State private var sidebarHandleHovered = false

    // The lifted state now lives on `schedule`; these keep the body readable.
    private var weekOffset: Int {
        get { schedule.weekOffset }
        nonmutating set { schedule.weekOffset = newValue }
    }
    private var scale: CalendarScale {
        get { schedule.scale }
        nonmutating set { schedule.scale = newValue }
    }
    private var showCancelled: Bool {
        get { schedule.showCancelled }
        nonmutating set { schedule.showCancelled = newValue }
    }

    init(
        controller: PortalController,
        preferences: Preferences,
        calendar: CalendarBridge,
        credentials: Credentials,
        schedule: ScheduleModel,
        updaterBridge: UpdaterBridge,
        onCheckForUpdates: @escaping () -> Void = {},
        settingsShowing: Bool = false
    ) {
        self.controller = controller
        self.preferences = preferences
        self.calendar = calendar
        self.credentials = credentials
        self.schedule = schedule
        self.updaterBridge = updaterBridge
        self.onCheckForUpdates = onCheckForUpdates
        self.settingsShowing = settingsShowing
        _editor = StateObject(wrappedValue: EventEditor(bridge: calendar))
    }

    private var weekStart: Date {
        let thisWeek = Weekday.weekStart(containing: .now)
        return Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: thisWeek) ?? thisWeek
    }

    private var year: Int { Calendar.current.component(.year, from: weekStart) }

    /// Classes and calendar events end up in one list so the grid draws one
    /// kind of thing and overlap layout can see across both.
    ///
    /// A class vacant this week is dropped from the grid — a cancelled class
    /// disappears — unless "Show Cancelled" is on, which brings it back faded so
    /// it can be restored. Vacancy is resolved per week, so a one-week vacancy
    /// only hides that week.
    private var blocks: [DayBlock] {
        let classes = controller.sessions
            .filter { showCancelled || preferences.status(for: $0, on: weekStart) != .vacant }
            .map { session -> DayBlock in
                let time = preferences.time(for: session, on: weekStart)
                return DayBlock(session, start: time.start, end: time.end)
            }
        return classes + calendar.events
    }

    private var canEdit: Bool { calendar.access == .granted }

    /// Feeds the floating month calendar's per-day color dots — capped to 4
    /// per weekday so a busy day's cell doesn't overflow.
    /// `ClassSession.subjectCodesByWeekday` is the pure/tested part; this is
    /// just the same `preferences.color(for:in:)` lookup `printWeek` already
    /// does per subject.
    private var weekdayColors: [Weekday: [Color]] {
        ClassSession.subjectCodesByWeekday(in: controller.sessions)
            .mapValues { codes in codes.prefix(4).map { preferences.color(for: $0, in: palette) } }
    }

    /// Straight copy of `AgendaView`'s `sidebarResizeHandle` — same drag
    /// convention, own state, since the two sidebars resize independently.
    private var scheduleSidebarResizeHandle: some View {
        Divider()
            .overlay(alignment: .center) {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
            }
            .background(sidebarHandleHovered ? palette.accent.opacity(0.3) : .clear)
            .onHover { inside in
                sidebarHandleHovered = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = sidebarWidthAtDragStart ?? preferences.scheduleSidebarWidth
                        if sidebarWidthAtDragStart == nil { sidebarWidthAtDragStart = start }
                        // The sidebar sits to the right of this handle: dragging
                        // left (negative dx) widens it.
                        preferences.setScheduleSidebarWidth(start - value.translation.width)
                    }
                    .onEnded { _ in sidebarWidthAtDragStart = nil }
            )
            .onTapGesture(count: 2) { preferences.resetScheduleSidebarWidth() }
            .help("Drag to resize · double-click to reset")
    }

    var body: some View {
        ZStack {
            palette.canvasWash.ignoresSafeArea()

            // Having a schedule is what decides the screen, not the session
            // state: a cached week beats a spinner, and beats an error too.
            if controller.sessions.isEmpty && calendar.events.isEmpty {
                startupState
            } else {
                HStack(spacing: 0) {
                    ZStack {
                        weekGrid
                            .id(weekStart)
                            .overlay(alignment: .bottom) {
                                if !selection.isEmpty {
                                    SelectionBar(
                                        count: selection.count,
                                        onDelete: deleteSelection,
                                        onDuplicate: duplicateSelection,
                                        onDone: { selection.removeAll() }
                                    )
                                    .padding(.bottom, 20)
                                }
                            }
                            // The year overlay below blurs and dims this
                            // instead of replacing it — the week grid stays
                            // visible underneath, per the floating-panel design.
                            .blur(radius: scale == .year ? 14 : 0)
                            .allowsHitTesting(scale == .week)

                        if scale == .year {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                                .onTapGesture { scale = .week }
                                .transition(.opacity)

                            YearView(
                                year: year, selectedWeekStart: weekStart,
                                weekdayColors: weekdayColors,
                                onSelect: { open($0) },
                                onAtTopChange: { atTop = $0 }
                            )
                            .frame(width: 640, height: 520)
                            .glassPanel(cornerRadius: 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .calendarScroll(enabled: !settingsShowing, scale: scale, atTop: atTop, perform: handleScroll)

                    scheduleSidebarResizeHandle
                    ScheduleSidebar(
                        lastUpdated: controller.lastUpdated,
                        refreshError: controller.refreshError ?? calendar.lastError,
                        update: updaterBridge.availableVersion,
                        onCheckForUpdates: onCheckForUpdates,
                        sessions: controller.sessions,
                        isVacant: { session, date in
                            preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
                        },
                        time: { session, date in
                            preferences.time(for: session, on: Weekday.weekStart(containing: date))
                        },
                        tint: { preferences.color(for: $0.subjectCode, in: palette) },
                        onRetry: retry,
                        onPrint: printWeek,
                        preferences: preferences
                    )
                    .frame(width: preferences.scheduleSidebarWidth)
                }
            }
        }
        .animation(Motion.arrival(reduced: reduceMotion), value: weekStart)
        .animation(Motion.arrival(reduced: reduceMotion), value: scale)
        // Palette is Equatable, so switching theme crossfades every colour at
        // once instead of snapping.
        .animation(Motion.drift(reduced: reduceMotion), value: palette)
        // The nav island drives the controls now: consume its step / new-event
        // intents here, where the week context and editor live.
        .onChange(of: schedule.stepIntent) { _, dir in
            guard dir != 0 else { return }
            step(dir)
            schedule.stepIntent = 0
        }
        .onChange(of: schedule.newEventIntent) { _, _ in newEventAtDefaultSlot() }
        .animation(Motion.arrival(reduced: reduceMotion), value: selection.isEmpty)
        .focusable()
        .onKeyPress(.escape) {
            if !selection.isEmpty { selection.removeAll(); return .handled }
            if scale == .year { scale = .week; return .handled }
            return .ignored
        }
        .onKeyPress(.delete) { deleteSelection(); return .handled }
        // Classes are excluded: they can't be deleted or duplicated, so
        // selecting them would offer actions that do nothing.
        .onKeyPress("a", phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection = Set(calendar.events.map(\.id))
            return .handled
        }
        .task {
            if controller.status == .idle {
                controller.signIn(with: credentials)
            }
        }
        .task(id: reloadKey) { reload() }
        // Reminders are rebuilt from here rather than from `PortalController`
        // so the schedule loader stays free of UI concerns — and because this
        // is the one view that already sees both the sessions and the settings.
        .task(id: notificationKey) {
            await Notifier.shared.refreshAuthorization()
            Notifier.shared.sync(controller.sessions, preferences)
        }
        // Keep the exported calendar in step with whole-term status: mark a
        // class online for the term and Calendar.app relabels it; mark it
        // vacant and it drops out — no manual re-export. Per-week status stays
        // out of this; a repeating series can't carry a single week's exception.
        .onChange(of: exportKey) { resyncCalendarExport() }
        // ...and when Calendar.app itself changes underneath us.
        .onReceive(NotificationCenter.default.publisher(for: .calendarStoreChanged)) { _ in
            reload()
        }
        .onAppear {
            editor.undoManager = undoManager
            editor.onChange = reload
            calendar.termEnd = preferences.termEndDate
        }
        .onChange(of: preferences.termEndDate) { calendar.termEnd = preferences.termEndDate }
        .confirmationDialog(
            "This event repeats.",
            isPresented: Binding(get: { pendingScope != nil }, set: { if !$0 { pendingScope = nil } }),
            titleVisibility: .visible
        ) {
            Button("This Event Only") { pendingScope?.apply(.thisEvent); pendingScope = nil }
            Button("All Future Events") { pendingScope?.apply(.futureEvents); pendingScope = nil }
            Button("Cancel", role: .cancel) { pendingScope = nil }
        }
    }

    private var weekGrid: some View {
        WeekGrid(
            blocks: blocks,
            weekStart: weekStart,
            selection: selection,
            recurringIDs: recurringIDs,
            preferences: preferences,
            editing: canEdit ? gridEditing : nil,
            onAtTopChange: { atTop = $0 }
        )
        .popover(
            item: $editing,
            attachmentAnchor: .rect(.rect(editing?.anchor ?? .zero)),
            arrowEdge: .trailing
        ) { request in
            EventEditorPopover(
                draft: request.draft,
                calendars: calendar.writableCalendars,
                existing: request.block,
                isRecurring: request.block.map { recurringIDs.contains($0.id) } ?? request.draft.isMultiDay,
                onCommit: { commit($0, for: request.block) },
                onDelete: request.block.map { block in { withScope(block) { editor.delete(block, scope: $0, inWeekStarting: weekStart) } } },
                onDuplicate: request.block.map { block in { editor.duplicate(block, inWeekStarting: weekStart) } }
            )
        }
    }

    private var gridEditing: WeekGrid.Editing {
        WeekGrid.Editing(
            create: startCreate,
            move: moveBlock,
            resize: resizeBlock,
            select: select,
            band: bandSelect,
            edit: startEdit,
            duplicate: { editor.duplicate($0, inWeekStarting: weekStart) },
            delete: { block in withScope(block) { editor.delete(block, scope: $0, inWeekStarting: weekStart) } }
        )
    }

    private func startEdit(_ block: DayBlock, anchor: CGRect) {
        guard let draft = editor.snapshot(of: block) else { return }
        editing = EditorRequest(block: block, anchor: anchor, draft: draft)
    }

    private var recurringIDs: Set<String> {
        Set(calendar.events.filter(calendar.isRecurring).map(\.id))
    }

    // MARK: Editing

    private func startCreate(_ range: DragRange, anchor: CGRect) {
        guard let calendarID = defaultCalendarID else { return }

        editing = EditorRequest(
            block: nil,
            anchor: anchor,
            draft: EventSnapshot(
                title: "",
                calendarID: calendarID,
                date: range.anchorDay.date(inWeekStarting: weekStart),
                start: range.start,
                end: range.end,
                repeatDays: range.days
            )
        )
    }

    private func commit(_ snapshot: EventSnapshot, for block: DayBlock?) {
        if let block {
            withScope(block) { scope in
                editor.rename(block, to: snapshot.title, scope: scope)
                editor.move(block, to: snapshot.date, start: snapshot.start,
                            end: snapshot.end, scope: scope)
                editor.setDetails(block, note: snapshot.note, link: snapshot.link, scope: scope)
            }
        } else {
            editor.create(snapshot, inWeekStarting: weekStart)
        }
    }

    private func moveBlock(_ block: DayBlock, to day: Weekday, start: Int, end: Int) {
        withScope(block) { scope in
            editor.move(block, to: day.date(inWeekStarting: weekStart),
                        start: start, end: end, scope: scope)
        }
    }

    private func resizeBlock(_ block: DayBlock, start: Int, end: Int) {
        withScope(block) { scope in
            editor.move(block, to: block.day.date(inWeekStarting: weekStart),
                        start: start, end: end, scope: scope, actionName: "Resize Event")
        }
    }

    /// Repeating events get asked; everything else applies straight away.
    /// Picking a scope silently would either orphan one occurrence or rewrite
    /// a whole series behind the user's back.
    ///
    /// Asked **once for the whole batch**. Looping and calling this per block
    /// overwrote a single `pendingScope` each time, so only the last block's
    /// question survived and the rest were silently dropped — which is why
    /// deleting a selection appeared to do nothing.
    private func withScope(_ blocks: [DayBlock], _ apply: @escaping (CalendarBridge.EditScope) -> Void) {
        if blocks.contains(where: calendar.isRecurring) {
            pendingScope = ScopeQuestion(apply: apply)
        } else {
            apply(.thisEvent)
        }
    }

    private func withScope(_ block: DayBlock, _ apply: @escaping (CalendarBridge.EditScope) -> Void) {
        withScope([block], apply)
    }

    private func deleteSelection() {
        let targets = calendar.events.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }

        withScope(targets) { scope in
            for block in targets {
                editor.delete(block, scope: scope, inWeekStarting: weekStart)
            }
            selection.removeAll()
        }
    }

    private func duplicateSelection() {
        for block in calendar.events where selection.contains(block.id) {
            editor.duplicate(block, inWeekStarting: weekStart)
        }
        selection.removeAll()
    }

    // MARK: Selection

    private func select(_ block: DayBlock?, mode: SelectionMode) {
        guard let block else {
            selection.removeAll()
            return
        }

        switch mode {
        case .replace:
            selection = [block.id]
        case .toggle:
            if selection.contains(block.id) { selection.remove(block.id) } else { selection.insert(block.id) }
        }
    }

    /// Classes are dropped: they can't be deleted or duplicated, so counting
    /// them made the bar say "3 selected" and then delete one.
    private func bandSelect(_ blocks: [DayBlock]) {
        selection = Set(blocks.filter { $0.session == nil }.map(\.id))
    }

    // MARK: Plumbing

    private var defaultCalendarID: String? {
        let writable = calendar.writableCalendars
        return (writable.first { preferences.visibleCalendarIDs.contains($0.id) } ?? writable.first)?.id
    }

    private var reloadKey: String {
        "\(weekStart.timeIntervalSince1970)-\(preferences.visibleCalendarIDs.sorted().joined())"
    }

    /// Everything a pending reminder depends on. Deliberately excludes
    /// `weekStart` — the schedule repeats weekly, so paging through weeks must
    /// not rewrite the notification set.
    private var notificationKey: String {
        [
            String(preferences.notificationsEnabled),
            String(preferences.notificationLeadMinutes),
            controller.sessions.map(\.id).joined(separator: ","),
            preferences.vacantSessionIDs.sorted().joined(separator: ","),
        ].joined(separator: "|")
    }

    /// Everything the export depends on — term defaults, per-week exceptions,
    /// and which calendars in-person and online go to — so changing any of them
    /// re-syncs. Picking the online calendar has to reach here, or the classes
    /// never move onto it.
    private var exportKey: String {
        let term = controller.sessions
            .map { "\($0.id):\(preferences.termStatus(for: $0).rawValue)" }
            .sorted()
        let perWeek = preferences.occurrenceStatuses
            .map { "\($0.key):\($0.value.rawValue)" }
            .sorted()
        return (term + perWeek + [preferences.exportCalendarID, preferences.onlineExportCalendarID])
            .joined(separator: ",")
    }

    /// Re-writes the exported classes so Calendar.app reflects the current term
    /// status. Only when the user has already chosen an export calendar — that
    /// choice is the consent to touch their calendar; without it, nothing is
    /// written behind their back.
    private func resyncCalendarExport() {
        guard calendar.access == .granted,
              !preferences.exportCalendarID.isEmpty,
              !controller.sessions.isEmpty
        else { return }

        _ = calendar.exportClasses(
            controller.sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            toCalendarID: preferences.exportCalendarID,
            onlineCalendarID: preferences.onlineExportCalendarID.isEmpty ? nil : preferences.onlineExportCalendarID,
            status: { preferences.status(for: $0, on: $1) },
            time: { preferences.time(for: $0, on: $1) }
        )
    }

    private func reload() {
        calendar.load(weekStart: weekStart, calendarIDs: preferences.visibleCalendarIDs)
        // Anything that vanished can't stay selected.
        let alive = Set(calendar.events.map(\.id))
        selection.formIntersection(alive)
    }

    private func open(_ date: Date, switchToWeek: Bool = true) {
        let thisWeek = Weekday.weekStart(containing: .now)
        let target = Weekday.weekStart(containing: date)
        let days = Calendar.current.dateComponents([.day], from: thisWeek, to: target).day ?? 0

        weekOffset = days / 7
        if switchToWeek { scale = .week }
    }

    private func retry() {
        controller.signIn(with: credentials)
    }

    /// Opens the system print panel on a stateless rendering of the browsed
    /// week. Its own "PDF ▾" menu (Save as PDF, Open in Preview, Mail…) is
    /// what actually produces a PDF — no custom PDF-writing code needed here.
    private func printWeek() {
        var colors: [String: Color] = [:]
        for block in blocks {
            colors[block.groupKey] = block.session.map { preferences.color(for: $0.subjectCode, in: .pupMaroon) }
                ?? preferences.color(forEvent: block.groupKey, in: .pupMaroon)
        }

        let hostingView = NSHostingView(rootView: WeekPrintView(blocks: blocks, weekStart: weekStart, colors: colors))
        hostingView.frame = CGRect(origin: .zero, size: WeekPrintLayout.pageSize(for: blocks))

        let info = NSPrintInfo.shared
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .fit

        NSPrintOperation(view: hostingView, printInfo: info).run()
    }

    /// A class is vacant this week, so the show/hide toggle is worth offering.
    private var hasVacantThisWeek: Bool {
        controller.sessions.contains { preferences.status(for: $0, on: weekStart) == .vacant }
    }

    /// The arrows move by whatever the current view shows, so they stay useful
    /// in the year view instead of nudging it a week at a time.
    private func step(_ direction: Int) {
        switch scale {
        case .week:
            weekOffset += direction
        case .year:
            if let target = Calendar.current.date(byAdding: .year, value: direction, to: weekStart) {
                open(target, switchToWeek: false)
            }
        }
    }

    private func handleScroll(_ action: CalendarScrollAction) {
        switch action {
        case .stepWeek(let direction): step(direction)
        case .zoomOut: scale = .year
        case .zoomIn: scale = .week // weekStart untouched — lands where you left
        }
    }

    private func newEventAtDefaultSlot() {
        let today = Date.now
        let inThisWeek = Weekday.weekStart(containing: today) == weekStart
        let day = inThisWeek ? Weekday.on(today) : .monday
        let hour = TimeSnap.snap(NowLine.minutes(of: today), to: 60)

        startCreate(DragRange(days: [day], start: hour, end: hour + 60), anchor: .zero)
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
                    .glassProminentButton()
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
}

/// An open editor, with the rect it should point at.
private struct EditorRequest: Identifiable {
    let id = UUID()
    let block: DayBlock?
    let anchor: CGRect
    let draft: EventSnapshot
}

/// A held-back edit, waiting for the user to say how far it should reach.
private struct ScopeQuestion {
    let apply: (CalendarBridge.EditScope) -> Void
}

