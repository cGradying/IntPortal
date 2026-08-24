import SwiftUI

/// A stateless rendering of one week for printing — no gestures, no hover, no
/// glass, no now-line, no live `Preferences` dependency. Reuses the same pure
/// layout math the live grid uses (`WeekPrintLayout`, `GridGeometry`,
/// `BlockLayout`, `BlockRuns`) so a printed week matches what's on screen,
/// just drawn onto paper instead of glass.
///
/// Always light, regardless of the app's theme — a dark palette's gridlines
/// (`Color.white.opacity(0.10)`) are invisible once printed.
struct WeekPrintView: View {
    let blocks: [DayBlock]
    let weekStart: Date
    /// Pre-resolved by the caller (one pass over `blocks`, via
    /// `preferences.color(for:in:)`/`.color(forEvent:in:)`) so this view never
    /// touches `Preferences` — keyed by `DayBlock.groupKey`.
    let colors: [String: Color]

    private var axis: (start: Int, end: Int) { WeekPrintLayout.axis(for: blocks) }
    private var hours: [Int] { stride(from: axis.start, through: axis.end, by: 60).map { $0 } }
    private var bodyHeight: CGFloat { WeekPrintLayout.bodyHeight(for: blocks) }
    private var geometry: GridGeometry { WeekPrintLayout.geometry(for: blocks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(weekTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)

            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: WeekPrintLayout.gutter)
                ForEach(Weekday.allCases) { day in
                    Text("\(day.short) \(dayNumber(day))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: WeekPrintLayout.headerHeight)

            HStack(alignment: .top, spacing: 0) {
                hourLabels
                    .frame(width: WeekPrintLayout.gutter)

                ZStack(alignment: .topLeading) {
                    hourLines
                    blockLayer
                }
                .frame(width: WeekPrintLayout.bodyWidth, height: bodyHeight)
            }
        }
        .padding(WeekPrintLayout.margin)
        .background(Color.white)
    }

    private var weekTitle: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(weekStart.formatted(format)) – \(end.formatted(format))"
    }

    private func dayNumber(_ day: Weekday) -> String {
        String(Calendar.current.component(.day, from: day.date(inWeekStarting: weekStart)))
    }

    private var hourLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { hour in
                Text(ClassSession.format(hour))
                    .font(.system(size: 8))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(height: WeekPrintLayout.hourHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.trailing, 6)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(hours.dropLast(), id: \.self) { _ in
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(height: 1)
                    .frame(height: WeekPrintLayout.hourHeight, alignment: .top)
            }
        }
        .frame(height: bodyHeight, alignment: .top)
    }

    /// Laid out per day so overlap lanes (`BlockLayout.arrange`) are computed
    /// within each column, matching how the live grid does it in
    /// `WeekGrid.placements(geometry:)`.
    private var blockLayer: some View {
        ForEach(Weekday.allCases) { day in
            ForEach(BlockLayout.arrange(blocks.filter { $0.day == day })) { placed in
                blockView(placed, day: day)
            }
        }
    }

    /// Split out from `blockLayer`'s `ForEach` closures — inlined, the nested
    /// generics plus the fill-color fallback made the type-checker time out.
    private func blockView(_ placed: BlockLayout.Placement, day: Weekday) -> some View {
        let block = placed.block
        let rect = geometry.rect(day: day, start: block.start, end: block.end)
        let fill: Color = colors[block.groupKey] ?? Palette.pupMaroon.color(for: block.title)

        return VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
            Text(block.subtitle)
                .font(.system(size: 7))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(3)
        .frame(width: max(rect.width * placed.width - 1, 1), height: max(rect.height, 14), alignment: .topLeading)
        .background(fill.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
        .offset(x: rect.minX + rect.width * placed.offset, y: rect.minY)
    }
}
