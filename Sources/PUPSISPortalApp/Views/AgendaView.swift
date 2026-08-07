import SwiftUI

/// Today, read top to bottom. A daily companion to the week grid: the class
/// happening now, what's already done, what's still coming with a countdown,
/// the free stretches between them, and a one-line look at tomorrow.
///
/// Display only — nothing here edits the schedule. It reads `appState.now`
/// (the shared minute clock) so it re-renders on the minute without a timer of
/// its own, the same clock the menu bar rides. The day's shape (which classes,
/// which phase, tomorrow's first) comes from the shared `DayAgenda` helper.
struct AgendaView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped true on first appear so the rows animate in once, on open, rather
    /// than re-staggering every minute the clock republishes.
    @State private var appeared = false

    private var now: Date { appState.now }
    private var nowMinutes: Int { NowLine.minutes(of: now) }
    private var weekStart: Date { Weekday.weekStart(containing: now) }

    /// The one reading of today, shared with the menu bar. Vacancy keys per
    /// week, and to the occurrence's own week for tomorrow.
    private var agenda: DayAgenda {
        DayAgenda.make(
            sessions: appState.portal.sessions,
            now: now,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            }
        )
    }

    var body: some View {
        ZStack {
            palette.canvasWash.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if agenda.items.isEmpty {
                        emptyState
                    } else {
                        timeline
                    }

                    tomorrowLine
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Today")
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide)))
                .font(Theme.Typo.detailTitle)
            Text(now.formatted(.dateTime.month(.wide).day()))
                .font(Theme.Typo.footer)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    // MARK: Timeline

    private var timeline: some View {
        let items = agenda.items
        return VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                classRow(item)
                    // Rows land in reading order on open, the same arrival the
                    // week grid uses. Reduce Motion → nil animation → instant.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(
                        Motion.arrival(reduced: reduceMotion)?
                            .delay(Motion.stagger(index, reduced: reduceMotion)),
                        value: appeared
                    )

                // The free stretch before the next class, so the day reads as a
                // timeline rather than a stack of cards.
                if index < items.count - 1 {
                    let next = items[index + 1].session
                    let free = next.start - item.session.end
                    if free >= 15 {
                        gapRow(minutes: free, passed: next.start <= nowMinutes)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func classRow(_ item: DayAgenda.Item) -> some View {
        let session = item.session
        let phase = item.phase
        let color = preferences.color(for: session.subjectCode, in: palette)
        let online = preferences.status(for: session, on: weekStart) == .online

        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4)
                .opacity(phase == .past ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.subjectCode)
                        .font(Theme.Typo.blockCode)
                    if online {
                        Image(systemName: "video.fill")
                            .font(Theme.Typo.detailMeta)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(session.description)
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(session.timeLabel)
                    .font(Theme.Typo.detailMeta)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            badge(for: session, phase: phase, color: color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowBackground(phase: phase))
        .opacity(phase == .past ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    /// One phrase per row for VoiceOver: subject, description, time, and where it
    /// sits in the day — mirrors `ClassBlock`'s composed label.
    private func accessibilityLabel(for item: DayAgenda.Item) -> String {
        let session = item.session
        let state: String
        switch item.phase {
        case .inSession: state = "in session"
        case .upcoming: state = upcoming(for: session).countdown(now: now)
        case .past: state = "done"
        }
        return "\(session.subjectCode), \(session.description), \(session.timeLabel), \(state)"
    }

    @ViewBuilder
    private func badge(for session: ClassSession, phase: ClassPhase, color: Color) -> some View {
        switch phase {
        case .inSession:
            Text("In session")
                .font(Theme.Typo.footer.weight(.semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(palette.accent.opacity(0.14), in: .capsule)
        case .upcoming:
            Text(upcoming(for: session).countdown(now: now))
                .font(Theme.Typo.footer.weight(.medium))
                .foregroundStyle(color)
        case .past:
            Text("Done")
                .font(Theme.Typo.detailMeta)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func rowBackground(phase: ClassPhase) -> some View {
        if phase == .inSession {
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.accent.opacity(0.10))
                .stroke(palette.accent.opacity(0.35), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.4))
        }
    }

    private func gapRow(minutes: Int, passed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .accessibilityHidden(true)
            Text("\(duration(minutes)) free")
        }
        .font(Theme.Typo.detailMeta)
        .foregroundStyle(.secondary)
        .opacity(passed ? 0.4 : 1)
        .padding(.leading, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tomorrow

    private var tomorrowLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "sunrise")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(tomorrowText)
                .font(Theme.Typo.footer)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var tomorrowText: String {
        guard let first = agenda.tomorrowFirst else { return "Tomorrow · nothing scheduled" }
        return "Tomorrow · \(first.subjectCode) at \(ClassSession.format(first.start))"
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No classes today",
            systemImage: "cup.and.saucer",
            description: Text("Enjoy the break — your week grid has the rest.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Helpers

    /// Wrap a today session as a `NextClass.Upcoming` so its countdown phrasing
    /// ("in 25 min" / "at 2PM") comes from the one place that owns it.
    private func upcoming(for session: ClassSession) -> NextClass.Upcoming {
        let cal = Calendar.current
        let midnight = session.day.date(inWeekStarting: weekStart)
        let start = cal.date(byAdding: .minute, value: session.start, to: midnight) ?? midnight
        return NextClass.Upcoming(session: session, start: start, isNow: false)
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}
