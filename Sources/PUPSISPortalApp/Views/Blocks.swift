import AppKit
import SwiftUI

/// A scraped class. Its time is SIS-owned and `ClassSession` itself is never
/// mutated — a local edit would be wiped by the next refresh, and
/// `ClassSession.id` is derived from start/end (`Models.swift:94`), so
/// mutating them would shift the very key an override is stored under. A
/// moved time lives in `Preferences` instead, resolved fresh on every read.
/// Colour, status, and time are all local overrides. The block still isn't
/// draggable — the popover below is the one edit surface for all three.
struct ClassBlock: View {
    let session: ClassSession
    /// The Monday of the week this block is drawn in, so status can be set for
    /// just this week rather than every week.
    let weekStart: Date
    let isPast: Bool
    let isSelected: Bool
    /// Where this sits in a run of consecutive days, so the shape can square
    /// off where it meets the next one.
    let position: RunPosition
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetail = false
    @State private var isHovering = false

    private var status: SessionStatus { preferences.status(for: session, on: weekStart) }
    private var color: Color { preferences.color(for: session.subjectCode, in: palette) }
    private var stripColor: Color { preferences.stripColor(for: session.subjectCode, in: palette) }
    /// Never `session.start`/`.end` directly — this is the moved time when
    /// one applies, which is the whole point of the override.
    private var resolvedTime: (start: Int, end: Int) { preferences.time(for: session, on: weekStart) }
    private var isTimeOverridden: Bool { preferences.isTimeOverridden(session, on: weekStart) }
    private var resolvedTimeLabel: String {
        "\(ClassSession.format(resolvedTime.start)) – \(ClassSession.format(resolvedTime.end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.subjectCode)
                .font(typography.blockCode)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 3) {
                if status != .regular {
                    Image(systemName: status.symbol)
                        .font(.system(size: 8))
                }
                Text(status == .vacant ? "Vacant" : resolvedTimeLabel)
                    .font(typography.blockTime)
                if isTimeOverridden {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8))
                }
                if !preferences.info(for: session).link.isEmpty {
                    Image(systemName: "link")
                        .font(.system(size: 8))
                }
            }
            .opacity(0.85)

            if !session.description.isEmpty {
                // No line limit — a tall block has the room to show all of it;
                // the clip on the block's own shape (below) is what keeps a
                // short block from bleeding into the row underneath, not a
                // line cap that would truncate even when there's space.
                Text(session.description)
                    .font(.system(size: 9))
                    .opacity(0.85)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Opaque on purpose. Glass belongs to the chrome; the blocks are the
        // content, and per-subject colour has to survive being looked at.
        .background(fill, in: BlockShape(position: position))
        // A short (15-30min) block doesn't have room for three lines — clip
        // to the block's own shape so the description crops away instead of
        // bleeding into the row below, rather than gating it on a measured
        // height that isn't available here.
        .clipShape(BlockShape(position: position))
        // A vacant class keeps its outline so the slot still reads as spoken
        // for — it just stops looking like something you have to attend. An
        // online class keeps its solid fill but gains a coloured strip so it
        // reads as online at a glance.
        .overlay {
            if status == .vacant {
                BlockShape(position: position)
                    .strokeBorder(color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else if status == .online {
                BlockShape(position: position)
                    .strokeBorder(stripColor, lineWidth: 2.5)
            }
        }
        .selectionRing(isSelected, palette: palette, reduced: reduceMotion, position: position)
        .foregroundStyle(status == .vacant ? AnyShapeStyle(color) : AnyShapeStyle(.white))
        .lift(isHovering, base: status == .vacant ? 0 : 0.18, reduced: reduceMotion)
        .opacity(isPast ? 0.45 : 1)
        .onHover { isHovering = $0 }
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
        return "\(session.subjectCode), \(session.description), \(resolvedTimeLabel)\(state)"
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
        Button("Change Colour…") { showingDetail = true }
        Button("Reset Colour") { preferences.resetColor(for: session.subjectCode) }
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

    private func presentStripPanel() {
        let preferences = preferences
        let subjectCode = session.subjectCode

        ColorPanelController.shared.present(current: stripColor, near: NSEvent.mouseLocation) { picked in
            preferences.setStripColor(picked, for: subjectCode)
        }
    }

    /// Sets this week's status. The term default is set separately by the
    /// "every week this term" toggle.
    private var statusBinding: Binding<SessionStatus> {
        Binding(
            get: { status },
            set: { preferences.setStatus($0, for: session, on: weekStart) }
        )
    }

    /// On when the current status is pinned across the whole term. Toggling it
    /// promotes this week's status to the term default, or clears the default
    /// back to in person.
    private var termBinding: Binding<Bool> {
        Binding(
            get: { preferences.termStatus(for: session) == status && status != .regular },
            set: { preferences.setTermStatus($0 ? status : .regular, for: session) }
        )
    }

    /// On when the note/link apply to every meeting of this subject rather
    /// than just this one. Flipping it moves the current value between scopes.
    private var permaBinding: Binding<Bool> {
        Binding(
            get: { preferences.hasPerma(for: session) },
            set: { preferences.setPerma($0, for: session) }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { preferences.info(for: session).note },
            set: { newValue in
                var info = preferences.info(for: session)
                info.note = newValue
                preferences.setInfo(info, for: session)
            }
        )
    }

    private var linkBinding: Binding<String> {
        Binding(
            get: { preferences.info(for: session).link },
            set: { newValue in
                var info = preferences.info(for: session)
                info.link = newValue
                preferences.setInfo(info, for: session)
            }
        )
    }

    private var joinURL: URL? {
        let link = preferences.info(for: session).link.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty, let url = URL(string: link), url.scheme != nil else { return nil }
        return url
    }

    /// On when the moved time applies to every week rather than just this one.
    private var everyWeekTimeBinding: Binding<Bool> {
        Binding(
            get: { preferences.isTermTimeOverridden(session) },
            set: { on in
                let time = resolvedTime
                if on {
                    preferences.setTime(nil, for: session, on: weekStart)
                    preferences.setTermTime(TimeOverride(start: time.start, end: time.end), for: session)
                } else {
                    preferences.setTermTime(nil, for: session)
                    preferences.setTime(TimeOverride(start: time.start, end: time.end), for: session, on: weekStart)
                }
            }
        )
    }

    private func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Writes to whichever scope the "Every week" toggle currently reads —
    /// never both, so flipping the toggle stays the one place scope changes.
    private func writeTime(start: Int, end: Int) {
        let override = TimeOverride(start: start, end: end)
        if everyWeekTimeBinding.wrappedValue {
            preferences.setTermTime(override, for: session)
        } else {
            preferences.setTime(override, for: session, on: weekStart)
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: resolvedTime.start) },
            set: { newDate in
                let newStart = minutes(from: newDate)
                writeTime(start: newStart, end: max(resolvedTime.end, newStart + TimeSnap.minimumDuration))
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: resolvedTime.end) },
            set: { newDate in
                let newEnd = minutes(from: newDate)
                writeTime(start: resolvedTime.start, end: max(newEnd, resolvedTime.start + TimeSnap.minimumDuration))
            }
        )
    }

    /// Back to the SIS time entirely — clears both tiers, not just this week's.
    private func resetTime() {
        preferences.setTime(nil, for: session, on: weekStart)
        preferences.setTermTime(nil, for: session)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.subjectCode)
                    .font(typography.detailTitle)
                Text(session.description)
                    .font(typography.detailBody)
                Text("\(session.day.short)  \(resolvedTimeLabel)")
                    .font(typography.detailMeta)
                    .foregroundStyle(.secondary)
                if !session.faculty.isEmpty {
                    Text(session.faculty)
                        .font(typography.detailBody)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                TextField("Description", text: noteBinding, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)

                HStack(spacing: 8) {
                    TextField("Online class link", text: linkBinding)
                        .textFieldStyle(.plain)
                    if let joinURL {
                        Button("Join") { NSWorkspace.shared.open(joinURL) }
                    }
                }

                Toggle("Apply to every \(session.subjectCode) block", isOn: permaBinding)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
                }
                .labelsHidden()

                Toggle("Every week", isOn: everyWeekTimeBinding)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                if isTimeOverridden {
                    HStack {
                        Text("SIS: \(session.timeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset", action: resetTime)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }

            Divider()

            Picker("Status", selection: statusBinding) {
                ForEach(SessionStatus.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            // Off by default: a status change is this week only until the user
            // says it's the whole term.
            Toggle("Every week this term", isOn: termBinding)
                .toggleStyle(.checkbox)
                .disabled(status == .regular)
                .font(.callout)

            if status == .online {
                Divider()
                Text("Online strip")
                    .font(typography.detailMeta)
                    .foregroundStyle(.secondary)
                SwatchRow(
                    current: stripColor,
                    onPick: { preferences.setStripColor($0, for: session.subjectCode) },
                    onCustom: presentStripPanel,
                    onReset: { preferences.resetStripColor(for: session.subjectCode) },
                    hasCustom: preferences.hasCustomStripColor(for: session.subjectCode)
                )
            }

            SwatchRow(
                current: color,
                onPick: { preferences.setColor($0, for: session.subjectCode) },
                onCustom: presentColorPanel,
                onReset: { preferences.resetColor(for: session.subjectCode) },
                hasCustom: preferences.hasCustomColor(for: session.subjectCode)
            )

            Text("Colour applies to every \(session.subjectCode) block. Status is this week unless you tick every week.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .tint(palette.accent)
    }
}

/// Inline colour choices. A `ColorPicker` alone opens the system colour panel
/// as its own floating window, which is a long way to go to recolour a block.
///
/// Takes its actions as closures so the same row drives both the subject colour
/// and the online strip colour without a second copy.
private struct SwatchRow: View {
    let current: Color
    let onPick: (Color) -> Void
    let onCustom: () -> Void
    let onReset: () -> Void
    let hasCustom: Bool
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(palette.subjectColors.enumerated()), id: \.offset) { _, swatch in
                Button {
                    onPick(swatch)
                } label: {
                    Circle()
                        .fill(swatch)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary, lineWidth: 2)
                                .opacity(swatch.hex == current.hex ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .help("Use this colour")
            }

            Button(action: onCustom) {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    ))
                    .frame(width: 20, height: 20)
                    .overlay { Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .help("Custom colour…")

            Spacer()

            Button("Reset", action: onReset)
                .buttonStyle(.link)
                .disabled(!hasCustom)
        }
    }
}

/// A calendar event. Plainer than a class because it isn't the app's data —
/// no colour or status controls — but unlike a class it can be moved, resized,
/// renamed and deleted.
struct EventBlock: View {
    let block: DayBlock
    let isPast: Bool
    let isSelected: Bool
    let isRecurring: Bool
    let position: RunPosition
    @ObservedObject var preferences: Preferences
    /// Nil when calendar access hasn't been granted, which makes the block
    /// read-only rather than offering menu items that can't work.
    let actions: Actions?
    let geometry: GridGeometry

    @Environment(\.palette) private var palette

    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    /// The block owns these rather than the interaction layer, because the
    /// layer sits underneath it — anything on top of a block has to handle its
    /// own clicks.
    struct Actions {
        let select: (SelectionMode) -> Void
        let edit: () -> Void
        let duplicate: () -> Void
        let delete: () -> Void
        let move: (Weekday, Int, Int) -> Void
        let resize: (Int, Int) -> Void
        /// Live feedback while a drag is in flight.
        let preview: (GridGesture?) -> Void
    }

    /// Height of the grab strip at the top and bottom edges.
    private let edgeGrab: CGFloat = 7

    /// Keyed by the run's group, so recolouring one day of a connected run
    /// recolours the whole run — which is what it looks like it should do.
    private var color: Color { preferences.color(forEvent: block.groupKey, in: palette) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(block.title)
                    .font(typography.blockCode)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isRecurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 8))
                        .opacity(0.7)
                }
            }
            Text(block.subtitle)
                .font(typography.blockTime)
                .opacity(0.85)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.22), in: BlockShape(position: position))
        .overlay(alignment: .leading) {
            // Only the first day of a run gets the accent edge; repeating it
            // mid-run would draw a seam through a continuous bar.
            if position.roundsLeft {
                Rectangle()
                    .fill(color)
                    .frame(width: 3)
                    .clipShape(BlockShape(position: position))
            }
        }
        .selectionRing(isSelected, palette: palette, reduced: reduceMotion, position: position)
        .foregroundStyle(.primary)
        .lift(isHovering, base: 0.12, reduced: reduceMotion)
        .opacity(isPast ? 0.45 : 1)
        .onHover { isHovering = $0 }
        .overlay(alignment: .top) { resizeHandle(.top) }
        .overlay(alignment: .bottom) { resizeHandle(.bottom) }
        .gesture(moveGesture)
        .onTapGesture(count: 2) { actions?.edit() }
        .onTapGesture {
            actions?.select(NSEvent.modifierFlags.isExtendingSelection ? .toggle : .replace)
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), \(block.subtitle)\(isRecurring ? ", repeating" : "")")
        .accessibilityHint("Double-click to edit")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let actions {
            Button("Edit…", action: actions.edit)
            Button("Duplicate", action: actions.duplicate)

            Divider()

            // A colour picker can't live in a menu, so the palette's own
            // colours go here by name and anything custom goes through Edit.
            Menu("Colour") {
                ForEach(Array(palette.subjectColors.enumerated()), id: \.offset) { index, swatch in
                    Button(Palette.colorName(at: index)) {
                        preferences.setEventColor(swatch, for: block.groupKey)
                    }
                }
                Divider()
                Button("Reset") { preferences.resetEventColor(for: block.groupKey) }
                    .disabled(!preferences.hasCustomEventColor(for: block.groupKey))
            }

            Divider()

            Button("Delete", role: .destructive, action: actions.delete)
        }
    }

    // MARK: Dragging

    /// 5pt rather than 3: a click with a slight twitch was committing a move,
    /// which wrote to the calendar every time you selected something.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(WeekGrid.gridSpace))
            .onChanged { value in
                guard let actions else { return }
                let bounds = shifted(by: value)
                actions.preview(.moving(id: block.id, day: bounds.day, start: bounds.start, end: bounds.end))
            }
            .onEnded { value in
                guard let actions else { return }
                let bounds = shifted(by: value)
                actions.preview(nil)

                // A drag that ended where it started is a click, not a move —
                // don't write to the calendar for nothing.
                guard bounds.day != block.day || bounds.start != block.start else { return }
                actions.move(bounds.day, bounds.start, bounds.end)
            }
    }

    /// Works entirely in grid coordinates, so it doesn't matter how wide the
    /// block is or which lane it sits in.
    ///
    /// The previous version reconstructed position from the block's full-column
    /// rect and its own `midX`, which was wrong the moment two blocks shared a
    /// slot and split the column between them.
    private func shifted(by value: DragGesture.Value) -> (day: Weekday, start: Int, end: Int) {
        let day = geometry.day(atX: value.location.x)

        // Track the pointer's own travel so the grab point stays under the
        // cursor and the block keeps its length.
        let shift = geometry.minutes(atY: value.location.y)
            - geometry.minutes(atY: value.startLocation.y)
        let duration = block.end - block.start
        let start = min(
            max(block.start + shift, geometry.axis.start),
            geometry.axis.end - duration
        )

        return (day, start, start + duration)
    }

    @ViewBuilder
    private func resizeHandle(_ edge: TimeSnap.Edge) -> some View {
        if let actions {
            Rectangle()
                .fill(.clear)
                .frame(height: edgeGrab)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(WeekGrid.gridSpace))
                        .onChanged { value in
                            let bounds = resized(edge, by: value)
                            actions.preview(.resizing(id: block.id, start: bounds.start, end: bounds.end))
                        }
                        .onEnded { value in
                            let bounds = resized(edge, by: value)
                            actions.preview(nil)

                            guard bounds.start != block.start || bounds.end != block.end else { return }
                            actions.resize(bounds.start, bounds.end)
                        }
                )
        }
    }

    /// The dragged edge simply goes wherever the pointer is — in grid
    /// coordinates that's a direct read, no offset arithmetic to get wrong.
    private func resized(_ edge: TimeSnap.Edge, by value: DragGesture.Value) -> (start: Int, end: Int) {
        TimeSnap.resize(
            start: block.start, end: block.end,
            movingEdge: edge,
            to: geometry.minutes(atY: value.location.y),
            axis: geometry.axis
        )
    }
}

// MARK: - Shared chrome

/// A block's outline, squared where it joins the next day so a run of
/// consecutive days reads as one bar rather than a row of separate boxes.
struct BlockShape: InsettableShape {
    let position: RunPosition
    var inset: CGFloat = 0

    private let radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: position.roundsLeft ? radius : 0,
            bottomLeadingRadius: position.roundsLeft ? radius : 0,
            bottomTrailingRadius: position.roundsRight ? radius : 0,
            topTrailingRadius: position.roundsRight ? radius : 0
        )
        .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> BlockShape {
        BlockShape(position: position, inset: inset + amount)
    }
}

private extension View {
    /// Selection is a ring, not a badge or a toolbar — the grid stays quiet
    /// and the ring says everything.
    func selectionRing(_ isSelected: Bool, palette: Palette, reduced: Bool, position: RunPosition) -> some View {
        overlay {
            BlockShape(position: position)
                .strokeBorder(palette.accent, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(Motion.selection(reduced: reduced), value: isSelected)
    }

    /// Pointer feedback. Without it nothing says a block is interactive until
    /// it's already been clicked.
    func lift(_ isHovering: Bool, base: Double, reduced: Bool) -> some View {
        shadow(
            color: .black.opacity(base == 0 ? 0 : (isHovering ? base + 0.14 : base)),
            radius: isHovering ? 5 : 1.5,
            y: isHovering ? 3 : 1
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .zIndex(isHovering ? 1 : 0)
        .animation(Motion.hover(reduced: reduced), value: isHovering)
    }
}
