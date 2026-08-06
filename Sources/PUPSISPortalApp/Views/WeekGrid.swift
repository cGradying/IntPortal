import SwiftUI

/// The week itself: hour rules, the floating day header, positioned blocks,
/// and the single interaction layer over the top of them.
struct WeekGrid: View {
    let blocks: [DayBlock]
    let weekStart: Date
    let selection: Set<String>
    let recurringIDs: Set<String>
    @ObservedObject var preferences: Preferences
    /// Nil when calendar access hasn't been granted — the grid stays read-only
    /// rather than offering drags that can't go anywhere.
    let editing: Editing?

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gesture: GridGesture?

    /// Everything the grid can do to the calendar, handed in from the shell.
    struct Editing {
        let create: (DragRange, CGRect) -> Void
        let move: (DayBlock, Weekday, Int, Int) -> Void
        let resize: (DayBlock, Int, Int) -> Void
        let select: (DayBlock?, SelectionMode) -> Void
        let band: ([DayBlock]) -> Void
        let edit: (DayBlock, CGRect) -> Void
        let duplicate: (DayBlock) -> Void
        let delete: (DayBlock) -> Void
    }

    private let gutter: CGFloat = 56
    private let headerHeight: CGFloat = 44
    private let hourHeight: CGFloat = 60
    /// Shared by the header and the grid so day labels line up with columns.
    private let columnInset: CGFloat = 12
    private let columnSpacing: CGFloat = 5
    static let gridSpace = "PUPSISPortal.grid"

    private var axis: (start: Int, end: Int) { GridAxis.hours(covering: blocks) }

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
                scrollingBody(height: bodyHeight, now: now)
                header(now: now)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: Chrome

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

    private func scrollingBody(height: CGFloat, now: Date) -> some View {
        let nowMinutes = NowLine.minutes(of: now)

        return ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels(now: showsNowLine(now) ? nowMinutes : nil)
                        .frame(width: gutter)

                    GeometryReader { proxy in
                        let geometry = GridGeometry(
                            width: proxy.size.width,
                            height: height,
                            axis: axis,
                            columnSpacing: columnSpacing
                        )

                        // Interaction layer *under* the blocks: on top it
                        // swallowed every click, including a class's colour
                        // and status menus. Empty space still reaches it,
                        // which is all it needs for create and rubber-band.
                        ZStack(alignment: .topLeading) {
                            hourLines(height: height)
                            interactionLayer(geometry: geometry)
                            blockLayer(geometry: geometry, now: now)
                        }
                        // Drags report positions in this space, so a block's
                        // gesture gets absolute grid coordinates rather than
                        // having to reconstruct where it is.
                        .coordinateSpace(.named(Self.gridSpace))
                    }
                    .frame(height: height)
                }
                .overlay(alignment: .topLeading) {
                    // Only the week that actually contains today gets a now-line.
                    if showsNowLine(now) {
                        NowLine(minutes: nowMinutes, axisStart: axis.start,
                                span: CGFloat(max(axis.end - axis.start, 60)),
                                height: height, gutter: gutter)
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, 12)
                .padding(.trailing, columnInset)
            }
            .onAppear {
                // Open on the current hour rather than at 6am. No animation:
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

    // MARK: Blocks

    private func blockLayer(geometry: GridGeometry, now: Date) -> some View {
        let placed = placements(geometry: geometry)
        // Only blocks that own their whole column can join a run. A block
        // sharing its column sits at half width, so bridging into it would
        // leave a nub reaching at nothing — and its neighbour has to know
        // that, which is why this is decided across the week rather than by
        // each block on its own.
        let solo = Set(placed.filter { $0.placement.lanes == 1 }.map(\.placement.block.id))
        let runs = BlockRuns.positions(for: blocks.filter { solo.contains($0.id) })

        return ForEach(Array(placed.enumerated()), id: \.element.id) { index, placed in
            let block = placed.placement.block
            let dragging = isDragging(block)
            let bounds = self.bounds(of: block)
            // Built from the dragged-to day, not the block's own — that's what
            // lets it cross columns while the pointer is down.
            let rect = geometry.rect(day: bounds.day, start: bounds.start, end: bounds.end)
            // A block in flight ignores lane splitting: it's above everything
            // and shouldn't shrink because of what it's passing over.
            let lanes = dragging ? 1 : placed.placement.lanes
            let lane = dragging ? 0 : placed.placement.lane
            let laneWidth = rect.width / CGFloat(lanes)
            // Dragging opts out of its run, so the block being moved reads as
            // one loose thing rather than dragging a bar behind it.
            let position = dragging ? .single : (runs[block.id] ?? .single)
            // Closing the gap is what makes consecutive days read as one bar.
            let bridge = position.bridgesRight ? columnSpacing + 2 : 0

            blockView(block, isPast: isPast(block, now: now), geometry: geometry, position: position)
                .frame(width: max(laneWidth - 2, 1) + bridge, height: max(rect.height, 26))
                .scaleEffect(dragging ? 1.03 : 1)
                .shadow(color: .black.opacity(dragging ? 0.35 : 0), radius: 8, y: 4)
                .offset(x: rect.minX + laneWidth * CGFloat(lane), y: rect.minY)
                .zIndex(dragging ? 10 : 0)
                .transition(
                    .opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading))
                    .animation(
                        Motion.arrival(reduced: reduceMotion)?
                            .delay(Motion.stagger(index, reduced: reduceMotion))
                    )
                )
                .background(alignment: .topLeading) { ghost(for: block, geometry: geometry) }
        }
    }

    /// Where the block came from, held open while it's being dragged. Without
    /// it there's nothing to change your mind against mid-drag.
    @ViewBuilder
    private func ghost(for block: DayBlock, geometry: GridGeometry) -> some View {
        if isDragging(block) {
            let origin = geometry.rect(day: block.day, start: block.start, end: block.end)
            let current = geometry.rect(day: bounds(of: block).day,
                                        start: bounds(of: block).start,
                                        end: bounds(of: block).end)

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.accent.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(palette.accent.opacity(0.08))
                )
                .frame(width: origin.width, height: max(origin.height, 26))
                // Positioned relative to the follower, which has already been
                // offset to the pointer.
                .offset(x: origin.minX - current.minX, y: origin.minY - current.minY)
                .transition(.opacity.animation(Motion.selection(reduced: reduceMotion)))
                .allowsHitTesting(false)
        }
    }

    private struct Placed: Identifiable {
        let day: Weekday
        let placement: BlockLayout.Placement
        var id: String { placement.id }
    }

    private func placements(geometry: GridGeometry) -> [Placed] {
        Weekday.allCases.flatMap { day in
            BlockLayout.arrange(blocks.filter { $0.day == day })
                .map { Placed(day: day, placement: $0) }
        }
    }

    @ViewBuilder
    private func blockView(
        _ block: DayBlock,
        isPast: Bool,
        geometry: GridGeometry,
        position: RunPosition
    ) -> some View {
        if let session = block.session {
            ClassBlock(
                session: session,
                weekStart: weekStart,
                isPast: isPast,
                isSelected: selection.contains(block.id),
                position: position,
                preferences: preferences
            )
        } else {
            EventBlock(
                block: block,
                isPast: isPast,
                isSelected: selection.contains(block.id),
                isRecurring: recurringIDs.contains(block.id),
                position: position,
                preferences: preferences,
                actions: editing.map { editing in
                    EventBlock.Actions(
                        select: { editing.select(block, $0) },
                        edit: {
                            editing.edit(block, geometry.rect(
                                day: block.day, start: block.start, end: block.end
                            ))
                        },
                        duplicate: { editing.duplicate(block) },
                        delete: { editing.delete(block) },
                        move: { editing.move(block, $0, $1, $2) },
                        resize: { editing.resize(block, $0, $1) },
                        preview: { gesture = $0 }
                    )
                },
                // Passed fresh each render rather than cached in @State: a
                // stale snapshot meant a zero width on the first frame and the
                // wrong axis after the grid resized, so drags resolved to the
                // wrong day and the wrong time.
                geometry: geometry
            )
        }
    }

    @ViewBuilder
    private func interactionLayer(geometry: GridGeometry) -> some View {
        if let editing {
            GridInteractionLayer(
                geometry: geometry,
                blocks: blocks,
                gesture: $gesture,
                onCreate: { range in
                    editing.create(range, geometry.rect(day: range.anchorDay, start: range.start, end: range.end))
                },
                onSelect: editing.select,
                onBand: editing.band
            )
        }
    }

    /// Where a block actually draws — its own slot, unless a drag is moving or
    /// resizing it right now, in which case it follows the pointer.
    ///
    /// The day matters as much as the times: without it a sideways drag
    /// redrew nothing, because the rect was still built from the block's
    /// original column.
    private func bounds(of block: DayBlock) -> (day: Weekday, start: Int, end: Int) {
        switch gesture {
        case .moving(let id, let day, let start, let end) where id == block.id:
            return (day, start, end)
        case .resizing(let id, let start, let end) where id == block.id:
            return (block.day, start, end)
        default:
            return (block.day, block.start, block.end)
        }
    }

    /// True while this block is the one being dragged.
    private func isDragging(_ block: DayBlock) -> Bool {
        switch gesture {
        case .moving(let id, _, _, _), .resizing(let id, _, _):
            return id == block.id
        default:
            return false
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

extension NSEvent.ModifierFlags {
    /// ⇧ or ⌘ both add to a selection rather than replacing it, matching every
    /// other Mac list.
    var isExtendingSelection: Bool {
        contains(.shift) || contains(.command)
    }
}
