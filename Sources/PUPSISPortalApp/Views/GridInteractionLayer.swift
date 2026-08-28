import AppKit
import SwiftUI
import Inject

/// What a gesture on the grid is currently doing.
enum GridGesture: Equatable {
    case creating(DragRange)
    case moving(id: String, day: Weekday, start: Int, end: Int)
    case resizing(id: String, start: Int, end: Int)
    case banding(CGRect)

    var draftRange: DragRange? {
        if case .creating(let range) = self { return range }
        return nil
    }
}

/// One transparent layer over the whole seven-column body.
///
/// The creation gesture used to live inside each day column, which is why a
/// horizontal drag could never cross into another day — the gesture belonged
/// to one column's `GeometryReader`. This owns the whole width and resolves
/// x itself through `GridGeometry`.
struct GridInteractionLayer: View {
    @ObserveInjection var inject
    let geometry: GridGeometry
    /// Blocks in the week, so a press can tell whether it landed on one.
    let blocks: [DayBlock]
    @Binding var gesture: GridGesture?

    let onCreate: (DragRange) -> Void
    let onSelect: (DayBlock?, SelectionMode) -> Void
    let onBand: ([DayBlock]) -> Void

    @Environment(\.palette) private var palette

    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the pointer last was, so the right-click menu knows which slot it
    /// opened on — SwiftUI's `contextMenu` doesn't report a location.
    @State private var hovered: CGPoint?
    /// Resolved once at drag start; a gesture must not change meaning halfway
    /// through because a modifier was released.
    @State private var isBanding = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase { hovered = point } else { hovered = nil }
            }
            .gesture(dragGesture)
            .onTapGesture { onSelect(nil, .replace) }
            .contextMenu { contextMenu }
            .overlay(alignment: .topLeading) { draftOverlay }
            .overlay(alignment: .topLeading) { bandOverlay }
            .enableInjection()
    }

    // MARK: Gesture

    /// Only empty space reaches this layer — blocks sit above it and handle
    /// their own moves, resizes and menus. So a drag here is either drawing a
    /// new event or sweeping a selection.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if gesture == nil {
                    // Read the modifier once, at the start: releasing ⌘ mid-drag
                    // must not turn a selection into a new event.
                    isBanding = NSEvent.modifierFlags.contains(.command)
                }

                gesture = isBanding
                    ? .banding(CGRect(from: value.startLocation, to: value.location))
                    : .creating(geometry.drag(from: value.startLocation, to: value.location))
            }
            .onEnded { _ in
                switch gesture {
                case .creating(let range):
                    onCreate(range)
                case .banding(let rect):
                    onBand(blocks.filter { intersects($0, rect) })
                default:
                    break
                }
                isBanding = false
                gesture = nil
            }
    }

    private func intersects(_ block: DayBlock, _ rect: CGRect) -> Bool {
        geometry.rect(day: block.day, start: block.start, end: block.end).intersects(rect)
    }

    // MARK: Overlays

    /// One rectangle across every day the drag covers, not one per day. The
    /// days from a drag are always consecutive, so the column gaps are part of
    /// the same block and drawing them as separate boxes was a lie about what
    /// was being created.
    @ViewBuilder
    private var draftOverlay: some View {
        if let range = gesture?.draftRange {
            let first = geometry.rect(day: range.anchorDay, start: range.start, end: range.end)
            let last = geometry.rect(day: range.days.last ?? range.anchorDay,
                                     start: range.start, end: range.end)

            VStack(alignment: .leading, spacing: 1) {
                Text(range.isMultiDay ? "New Events" : "New Event")
                    .font(typography.blockCode)
                Text("\(ClassSession.format(range.start)) – \(ClassSession.format(range.end))")
                    .font(typography.blockTime)
                if range.isMultiDay {
                    Text(range.days.map(\.short).map { $0.capitalized }.joined(separator: ", "))
                        .font(typography.blockTime)
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: last.maxX - first.minX, height: first.height, alignment: .topLeading)
            .background(palette.accent.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .foregroundStyle(palette.accent)
            .offset(x: first.minX, y: first.minY)
            .animation(Motion.drag(reduced: reduceMotion), value: range)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var bandOverlay: some View {
        if case .banding(let rect) = gesture {
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.accent.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(palette.accent.opacity(0.6), lineWidth: 1)
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        let point = hovered ?? .zero
        let day = geometry.day(atX: point.x)
        let start = TimeSnap.snap(geometry.minutes(atY: point.y), to: 60)

        Button("New Event at \(ClassSession.format(start))") {
            onCreate(DragRange(days: [day], start: start, end: min(start + 60, geometry.axis.end)))
        }
    }
}

/// How a click changes the selection.
enum SelectionMode {
    case replace
    case toggle
}

private extension CGRect {
    /// A rectangle from two drag points, whichever way round they were drawn.
    init(from: CGPoint, to: CGPoint) {
        self.init(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
    }
}
