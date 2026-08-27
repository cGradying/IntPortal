import SwiftUI

/// Twelve months at once, the way Apple Calendar's year view works: a place to
/// see where you are and jump somewhere, not a place to read a schedule.
/// Picking any date opens that week in the grid.
struct YearView: View {
    /// The months to show, in order — a compact 4-month window around
    /// wherever's currently browsed (`MonthLayout.months(around:count:)`),
    /// not a calendar-year slice. Presentation-only: the view just lays out
    /// whatever it's given.
    let months: [Date]
    /// The week currently open in the grid, so it can be marked here.
    let selectedWeekStart: Date
    /// Per-weekday dot colors — a subject's *normal* meeting day, resolved
    /// once by the caller (`CalendarView.weekdayColors`), not recomputed
    /// per cell.
    var weekdayColors: [Weekday: [Color]] = [:]
    /// Custom-calendar-event dot colors, keyed by `startOfDay` — the
    /// date-specific sibling to `weekdayColors`' recurring pattern (see
    /// `CalendarView.eventDotsByDate`).
    var eventDotsByDate: [Date: [Color]] = [:]
    let onSelect: (Date) -> Void

    @Environment(\.palette) private var palette

    @Environment(\.typography) private var typography

    // 2 columns — a 2×2 popup for 4 months, not the wide 4-column strip a
    // full year needed.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 56), count: 2)

    // No ScrollView: a fixed 4-month grid has one size, and a scrollable
    // container the content doesn't fill is exactly the "excess space"
    // this was asked to stop doing — the panel now sizes to its content
    // instead of to an arbitrary fixed height.
    var body: some View {
        LazyVGrid(columns: columns, spacing: 56) {
            ForEach(months, id: \.self) { month in
                MonthGrid(
                    month: month,
                    selectedWeekStart: selectedWeekStart,
                    weekdayColors: weekdayColors,
                    eventDotsByDate: eventDotsByDate,
                    onSelect: onSelect
                )
            }
        }
        .padding(44)
    }
}

private struct MonthGrid: View {
    let month: Date
    let selectedWeekStart: Date
    let weekdayColors: [Weekday: [Color]]
    let eventDotsByDate: [Date: [Color]]
    let onSelect: (Date) -> Void

    @Environment(\.palette) private var palette

    @Environment(\.typography) private var typography

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(typography.screenTitle)
                .foregroundStyle(palette.accent)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Weekday.allCases) { day in
                    Text(day.short.prefix(1))
                        .font(typography.gutter)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(MonthLayout.days(ofMonthContaining: month), id: \.self) { date in
                    let day = Calendar.current.startOfDay(for: date)
                    DayCell(
                        date: date,
                        isInMonth: MonthLayout.isSameMonth(date, as: month),
                        isInSelectedWeek: Weekday.weekStart(containing: date) == selectedWeekStart,
                        dotColors: Array((weekdayColors[Weekday.on(date)] ?? []) + (eventDotsByDate[day] ?? []).prefix(4)),
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
    /// Already resolved for this date — recurring weekday pattern plus any
    /// custom events on this exact day, combined by `MonthGrid`.
    var dotColors: [Color] = []
    let onSelect: (Date) -> Void

    @Environment(\.palette) private var palette

    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Button {
            onSelect(date)
        } label: {
            VStack(spacing: 3) {
                Text(String(Calendar.current.component(.day, from: date)))
                    .font(typography.detailBody)
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
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

                HStack(spacing: 3) {
                    ForEach(Array(dotColors.prefix(4).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
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
        if isToday { return Color.legibleForeground(on: palette.accent) }
        return isInMonth ? .primary : .secondary.opacity(0.5)
    }
}
