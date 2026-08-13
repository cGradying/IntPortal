import SwiftUI

/// The app's one piece of floating chrome. It starts centred in the window (a
/// home launcher), and flies to the top when a destination opens. Idle at the
/// top it's a compact pill; hovering morphs it into the full bar — nav +
/// (Stage 2) the active screen's controls + Settings.
///
/// Glass because it's chrome, never content; untinted (tint is the now-line's
/// alone). One resizing capsule, so no `GlassEffectContainer` is needed.
struct NavIsland: View {
    @ObservedObject var appState: AppState
    @ObservedObject var schedule: ScheduleModel
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight
    @State private var hovered = false

    private static let items: [Destination] = [.schedule, .today, .grades]

    /// Boxy with a little curve — not a full capsule.
    private var islandShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        content
            .padding(6)
            .glassInteractive(in: islandShape)
            .onHover { hovered = $0 }
            .animation(Motion.island(reduced: reduceMotion), value: hovered)
            .animation(Motion.island(reduced: reduceMotion), value: appState.isHome)
    }

    @ViewBuilder private var content: some View {
        if appState.isHome {
            homeLayout
        } else if hovered || !preferences.islandExpandOnHover {
            expandedBar
        } else {
            compactPill
        }
    }

    // MARK: Home — centred launcher: a glance line above the destination tabs.

    private var homeLayout: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(Self.homeDate.string(from: appState.now))
                    .font(Theme.Typo.screenTitle)
                Text(glance)
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 4)
            HStack(spacing: 4) {
                ForEach(Self.items) { segment($0) }
            }
            settingsButton
                .padding(.top, -2)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: Active + hovered — the full bar.

    private var expandedBar: some View {
        HStack(spacing: 4) {
            homeButton
            Divider().frame(height: 14)
            ForEach(Self.items) { segment($0) }
            if appState.selection == .schedule {
                scheduleControls
            }
            Divider().frame(height: 14)
            settingsButton
        }
    }

    /// The Schedule screen's controls, now living in the island (they drive
    /// `schedule`; the view consumes step/new-event via intents).
    @ViewBuilder private var scheduleControls: some View {
        Divider().frame(height: 14)
        Picker("View", selection: $schedule.scale) {
            ForEach(CalendarScale.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        iconButton("chevron.left", "Previous") { schedule.stepIntent = -1 }
        Button("Today") { schedule.weekOffset = 0 }
            .buttonStyle(.plain).font(Theme.Typo.dayName)
            .foregroundStyle(schedule.weekOffset == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .disabled(schedule.weekOffset == 0)
        iconButton("chevron.right", "Next") { schedule.stepIntent = 1 }
        if schedule.scale == .week {
            iconButton(schedule.showCancelled ? "eye" : "eye.slash", "Show or hide cancelled") {
                schedule.showCancelled.toggle()
            }
        }
        iconButton("plus", "New event") { schedule.newEventIntent += 1 }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: Active + idle — a compact pill with a glance.

    private var compactPill: some View {
        let dest = appState.selection
        return HStack(spacing: 7) {
            Image(systemName: dest.symbol).font(.system(size: 12, weight: .medium))
            Text(dest.title).font(Theme.Typo.dayName)
            Text("·").foregroundStyle(.secondary)
            Text(glance).font(Theme.Typo.footer).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    // MARK: Pieces

    private func segment(_ item: Destination) -> some View {
        let isSelected = appState.selection == item && !appState.isHome
        return Button {
            withAnimation(Motion.island(reduced: reduceMotion)) { appState.open(item) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 12, weight: .medium))
                Text(item.title).font(Theme.Typo.dayName)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background {
                if isSelected {
                    Capsule()
                        .fill(.primary.opacity(0.12))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var homeButton: some View {
        Button {
            withAnimation(Motion.island(reduced: reduceMotion)) { appState.isHome = true }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Home")
    }

    private var settingsButton: some View {
        Button { appState.showingSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
    }

    /// The next class, or the weekday when nothing's coming up.
    private var glance: String {
        if let up = appState.upcoming {
            return "\(up.session.subjectCode) \(up.countdown(now: appState.now))"
        }
        return Self.weekday.string(from: appState.now)
    }

    private static let homeDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
}
