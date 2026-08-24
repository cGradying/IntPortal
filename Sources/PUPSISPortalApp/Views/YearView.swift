import SwiftUI

/// Twelve months at once, the way Apple Calendar's year view works: a place to
/// see where you are and jump somewhere, not a place to read a schedule.
/// Picking any date opens that week in the grid.
struct YearView: View {
    let year: Int
    /// The week currently open in the grid, so it can be marked here.
    let selectedWeekStart: Date
    let onSelect: (Date) -> Void
    /// Fires whenever the scroll position pins to (or leaves) the top —
    /// what `CalendarScroll` gates the year↔week overscroll switch on.
    var onAtTopChange: (Bool) -> Void = { _ in }

    @Environment(\.palette) private var palette

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 4)
    private static let scrollSpace = "PUPSISPortal.yearScroll"

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(MonthLayout.months(in: year), id: \.self) { month in
                    MonthGrid(
                        month: month,
                        selectedWeekStart: selectedWeekStart,
                        onSelect: onSelect
                    )
                }
            }
            .padding(24)
            .trackScrollTop(space: Self.scrollSpace) { onAtTopChange($0 >= -1) }
        }
        .coordinateSpace(.named(Self.scrollSpace))
        .scrollIndicators(.hidden)
    }
}

private struct MonthGrid: View {
    let month: Date
    let selectedWeekStart: Date
    let onSelect: (Date) -> Void

    @Environment(\.palette) private var palette

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(Theme.Typo.detailTitle)
                .foregroundStyle(palette.accent)

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Weekday.allCases) { day in
                    Text(day.short.prefix(1))
                        .font(Theme.Typo.gutter)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(MonthLayout.days(ofMonthContaining: month), id: \.self) { date in
                    DayCell(
                        date: date,
                        isInMonth: MonthLayout.isSameMonth(date, as: month),
                        isInSelectedWeek: Weekday.weekStart(containing: date) == selectedWeekStart,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isInMonth: Bool
    let isInSelectedWeek: Bool
    let onSelect: (Date) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Button {
            onSelect(date)
        } label: {
            Text(String(Calendar.current.component(.day, from: date)))
                .font(Theme.Typo.gutter)
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background {
                    if isToday {
                        Circle().fill(palette.accent)
                    } else if isInSelectedWeek {
                        // The open week reads as a band across the row, which
                        // is what actually tells you where you are.
                        Rectangle().fill(palette.accent.opacity(0.14))
                    } else if isHovering {
                        Circle().fill(palette.accent.opacity(0.2))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Motion.hover(reduced: reduceMotion), value: isHovering)
        .animation(Motion.hover(reduced: reduceMotion), value: isInSelectedWeek)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityHint("Show this week")
    }

    private var foreground: Color {
        if isToday { return .white }
        return isInMonth ? .primary : .secondary.opacity(0.5)
    }
}
