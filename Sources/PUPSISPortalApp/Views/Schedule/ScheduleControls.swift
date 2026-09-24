import SwiftUI

/// Schedule's own controls — ‹ range › paging, Today, Week | COR | Year,
/// Show cancelled, New event, Refresh (spec 03 change 1).
///
/// Plain values, bindings and closures only, no `AppState`/`ScheduleModel`
/// reference, so it drops into any container and snapshots on its own. It
/// sits in a slim row above the COR strip inside `CalendarView` until the IS
/// slice moves it into a floating controls island shared by every screen.
struct ScheduleControls: View {
    @Binding var scale: CalendarScale
    @Binding var showCancelled: Bool
    let weekOffset: Int
    let isRefreshing: Bool
    let onStep: (Int) -> Void
    let onToday: () -> Void
    let onNewEvent: () -> Void
    let onRefresh: () -> Void

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    /// Week | COR | Year. COR isn't a real `CalendarScale` yet — its table
    /// lands in SC2 — so this is a display-only third rung that stays
    /// disabled until then rather than a case `CalendarScale` itself has to
    /// grow (and every other `switch` over it has to learn).
    private enum Tab: String, CaseIterable, Identifiable {
        case week, cor, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week: "Week"
            case .cor: "COR"
            case .year: "Year"
            }
        }
    }

    private var tab: Binding<Tab> {
        Binding(
            get: { scale == .year ? .year : .week },
            set: { newValue in
                switch newValue {
                case .week: scale = .week
                case .year: scale = .year
                case .cor: break // disabled below; never actually chosen
                }
            }
        )
    }

    private var weekRangeLabel: String {
        let start = Calendar.current.date(
            byAdding: .day, value: weekOffset * 7, to: Weekday.weekStart(containing: .now)
        ) ?? .now
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(short)) – \(end.formatted(short))"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button { onStep(-1) } label: { PixelIcon(.left) }
                .buttonStyle(.pixelSmall)
                .accessibilityLabel("Previous")
            if scale == .week {
                Text(weekRangeLabel)
                    .font(typography.numeric(size: 13))
                    .foregroundStyle(palette.roles.ink2)
            }
            Button("Today", action: onToday)
                .buttonStyle(.pixelSmall)
                .disabled(weekOffset == 0)
            Button { onStep(1) } label: { PixelIcon(.right) }
                .buttonStyle(.pixelSmall)
                .accessibilityLabel("Next")
            Picker("View", selection: tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.label)
                        .tag(tab)
                        .disabled(tab == .cor)
                        .help(tab == .cor ? "Coming in SC2" : "")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if scale == .week {
                Button(showCancelled ? "Hide cancelled" : "Show cancelled") { showCancelled.toggle() }
                    .buttonStyle(.pixelSmall)
            }
            Spacer(minLength: 0)
            Button("New event", action: onNewEvent)
                .buttonStyle(.pixelSecondary)
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    PixelIcon(.refresh)
                    Text(isRefreshing ? "Refreshing…" : "Refresh")
                }
            }
            .buttonStyle(.pixelPrimary)
            .disabled(isRefreshing)
        }
    }
}
