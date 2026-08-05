import AppKit
import SwiftUI

/// A scraped class. Its time is SIS-owned, so it can't be moved or resized —
/// a local edit would be wiped by the next refresh. Colour and status are
/// local overrides, and those it does own.
struct ClassBlock: View {
    let session: ClassSession
    let isPast: Bool
    let isSelected: Bool
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetail = false
    @State private var isHovering = false

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
        // content, and per-subject colour has to survive being looked at.
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        // A vacant class keeps its outline so the slot still reads as spoken
        // for — it just stops looking like something you have to attend.
        .overlay {
            if status == .vacant {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .selectionRing(isSelected, palette: palette, reduced: reduceMotion)
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

            SubjectSwatches(
                subjectCode: session.subjectCode,
                current: color,
                preferences: preferences,
                onCustom: presentColorPanel
            )

            Text("Colour applies to every \(session.subjectCode) block; status is just this meeting.")
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
private struct SubjectSwatches: View {
    let subjectCode: String
    let current: Color
    @ObservedObject var preferences: Preferences
    let onCustom: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(palette.subjectColors.enumerated()), id: \.offset) { _, swatch in
                Button {
                    preferences.setColor(swatch, for: subjectCode)
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

            Button("Reset") { preferences.resetColor(for: subjectCode) }
                .buttonStyle(.link)
                .disabled(!preferences.hasCustomColor(for: subjectCode))
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
    /// Nil when calendar access hasn't been granted, which makes the block
    /// read-only rather than offering menu items that can't work.
    let actions: Actions?
    let geometry: GridGeometry

    @Environment(\.palette) private var palette
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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(block.title)
                    .font(Theme.Typo.blockCode)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isRecurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 8))
                        .opacity(0.7)
                }
            }
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
        .selectionRing(isSelected, palette: palette, reduced: reduceMotion)
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

private extension View {
    /// Selection is a ring, not a badge or a toolbar — the grid stays quiet
    /// and the ring says everything.
    func selectionRing(_ isSelected: Bool, palette: Palette, reduced: Bool) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 8)
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
