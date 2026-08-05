import Foundation

/// One thing drawn in one column. Classes repeat every week; calendar events
/// belong to a date. Flattening both to "a weekday plus minutes" is what lets
/// the grid draw one kind of thing instead of two.
struct DayBlock: Identifiable, Equatable {
    enum Source: Equatable {
        case sisClass(ClassSession)
        case calendarEvent(identifier: String)
    }

    let id: String
    let day: Weekday
    /// Minutes from midnight.
    let start: Int
    let end: Int
    let title: String
    let subtitle: String
    let source: Source

    var duration: Int { max(end - start, 0) }

    var session: ClassSession? {
        if case .sisClass(let session) = source { return session }
        return nil
    }

    init(_ session: ClassSession) {
        id = "class-\(session.id)"
        day = session.day
        start = session.start
        end = session.end
        title = session.subjectCode
        subtitle = session.timeLabel
        source = .sisClass(session)
    }

    init(id: String, day: Weekday, start: Int, end: Int, title: String, subtitle: String) {
        self.id = "event-\(id)"
        self.day = day
        self.start = start
        self.end = end
        self.title = title
        self.subtitle = subtitle
        source = .calendarEvent(identifier: id)
    }
}

/// The vertical range the grid draws.
enum GridAxis {
    /// A normal waking day. Fitting the axis to the blocks alone made the grid
    /// jump around as the schedule changed — a 1:30pm–6:30pm week rendered a
    /// completely different shape from a 7:30am one.
    static let defaultWindow = (start: 6 * 60, end: 22 * 60)

    /// Never narrower than the window, and never clips a block: a 6am lab or a
    /// class running past 10pm pushes the edge out rather than being cut off.
    /// Whole hours, so the labels line up with the hour rules.
    static func hours(
        covering blocks: [DayBlock],
        window: (start: Int, end: Int) = defaultWindow
    ) -> (start: Int, end: Int) {
        let earliest = blocks.map(\.start).min().map { ($0 / 60) * 60 }
        let latest = blocks.map(\.end).max().map { Int(ceil(Double($0) / 60)) * 60 }

        return (
            min(window.start, earliest ?? window.start),
            max(window.end, latest ?? window.end)
        )
    }
}

/// Side-by-side placement for blocks that share a time slot. Without this, a
/// class and a calendar event at the same hour draw on top of each other and
/// the one underneath is simply invisible.
enum BlockLayout {
    struct Placement: Equatable, Identifiable {
        let block: DayBlock
        /// Which sub-column this block sits in.
        let lane: Int
        /// How many sub-columns its overlapping cluster needs.
        let lanes: Int

        var id: String { block.id }
    }

    /// Blocks are grouped into clusters of transitively-overlapping blocks, so
    /// width is divided only among things that actually collide — one busy
    /// afternoon doesn't shrink the whole day.
    static func arrange(_ blocks: [DayBlock]) -> [Placement] {
        let sorted = blocks.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        var placements: [Placement] = []

        var cluster: [(block: DayBlock, lane: Int)] = []
        var laneEnds: [Int] = []
        var clusterEnd = Int.min

        func flush() {
            let lanes = max(laneEnds.count, 1)
            placements += cluster.map { Placement(block: $0.block, lane: $0.lane, lanes: lanes) }
            cluster.removeAll()
            laneEnds.removeAll()
            clusterEnd = Int.min
        }

        for block in sorted {
            // Touching edges aren't an overlap: a 3–6pm and a 6–9pm class are
            // consecutive, and splitting them in half would be wrong.
            if block.start >= clusterEnd { flush() }

            let lane = laneEnds.firstIndex { $0 <= block.start } ?? laneEnds.count
            if lane == laneEnds.count {
                laneEnds.append(block.end)
            } else {
                laneEnds[lane] = block.end
            }

            cluster.append((block, lane))
            clusterEnd = max(clusterEnd, block.end)
        }
        flush()

        return placements
    }
}
