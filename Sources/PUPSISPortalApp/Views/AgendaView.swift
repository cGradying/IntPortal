import SwiftUI

/// Today, read top to bottom. A daily companion to the week grid: the class
/// happening now, what's already done, what's still coming with a countdown,
/// the free stretches between them, and a one-line look at tomorrow.
///
/// It folds the user's own calendar events (from the calendars ticked for the
/// grid) in beside classes, so the free-time gaps reflect the whole day, not
/// just class meetings.
///
/// Display only — nothing here edits the schedule. It reads `appState.now`
/// (the shared minute clock) so it re-renders on the minute without a timer of
/// its own, the same clock the menu bar rides.
struct AgendaView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var notes: NotesStore
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped true on first appear so the rows animate in once, on open, rather
    /// than re-staggering every minute the clock republishes.
    @State private var appeared = false

    /// The note key of the tapped Today row, or nil for none — drives the
    /// per-item note in the side panel.
    @State private var selectedKey: String?

    private var now: Date { appState.now }
    private var nowMinutes: Int { NowLine.minutes(of: now) }
    private var weekStart: Date { Weekday.weekStart(containing: now) }

    /// Today's classes as vacancy-aware phased items — still the source of the
    /// tomorrow line and the empty state.
    private var agenda: DayAgenda {
        DayAgenda.make(
            sessions: appState.portal.sessions,
            now: now,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            }
        )
    }

    /// Classes merged with today's custom calendar events, sorted and phased.
    private var entries: [DayAgenda.AgendaEntry] {
        DayAgenda.timeline(
            classes: appState.portal.sessions,
            events: calendar.todayBlocks(calendarIDs: preferences.visibleCalendarIDs, on: now),
            now: now,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                palette.canvasWash.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header

                        if entries.isEmpty {
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

            Divider()

            NotesPanel(
                notes: notes,
                dayKey: dayKey,
                selectedKey: selectedKey,
                selectedTitle: selectedTitle
            )
            .frame(width: 320)
        }
        .navigationTitle("Today")
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide)))
                .font(Theme.Typo.detailTitle)
            HStack(spacing: 6) {
                Text(now.formatted(.dateTime.month(.wide).day()))
                let free = DayAgenda.remainingFreeMinutes(entries, nowMinutes: nowMinutes)
                if free > 0 {
                    Text("·")
                    Text("\(duration(free)) free")
                }
            }
            .font(Theme.Typo.footer)
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    // MARK: Timeline

    private var timeline: some View {
        let items = entries
        return VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                row(for: entry)
                    // Rows land in reading order on open, the same arrival the
                    // week grid uses. Reduce Motion → nil animation → instant.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(
                        Motion.arrival(reduced: reduceMotion)?
                            .delay(Motion.stagger(index, reduced: reduceMotion)),
                        value: appeared
                    )

                // The free stretch before the next entry, so the day reads as a
                // timeline rather than a stack of cards.
                if index < items.count - 1 {
                    let next = items[index + 1]
                    let free = next.start - entry.end
                    if free >= 15 {
                        gapRow(minutes: free, passed: next.start <= nowMinutes)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: DayAgenda.AgendaEntry) -> some View {
        let key = noteKey(entry)
        let selected = key == selectedKey

        Group {
            if let session = entry.session {
                classRow(entry, session: session, hasNote: notes.hasNote(for: key))
            } else {
                eventRow(entry, hasNote: notes.hasNote(for: key))
            }
        }
        // The whole row is the note target; tapping again clears the selection.
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = selected ? nil : key }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.accent.opacity(selected ? 0.5 : 0), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func classRow(_ entry: DayAgenda.AgendaEntry, session: ClassSession, hasNote: Bool) -> some View {
        let phase = entry.phase
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
                    if hasNote { noteDot }
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

            classBadge(for: session, phase: phase, color: color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowBackground(phase: phase))
        .opacity(phase == .past ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(classLabel(session, phase: phase))
    }

    /// A calendar event — the user's own commitments folded in. Neutral strip,
    /// no subject color or online marker; those belong to classes.
    @ViewBuilder
    private func eventRow(_ entry: DayAgenda.AgendaEntry, hasNote: Bool) -> some View {
        let phase = entry.phase

        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.secondary)
                .frame(width: 4)
                .opacity(phase == .past ? 0.3 : 0.7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(Theme.Typo.blockCode)
                        .lineLimit(1)
                    if hasNote { noteDot }
                }
                Text(entry.subtitle)
                    .font(Theme.Typo.detailMeta)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            eventBadge(entry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowBackground(phase: phase))
        .opacity(phase == .past ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title), \(entry.subtitle), \(phaseWord(phase))")
    }

    // MARK: Badges

    @ViewBuilder
    private func classBadge(for session: ClassSession, phase: ClassPhase, color: Color) -> some View {
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
    private func eventBadge(_ entry: DayAgenda.AgendaEntry) -> some View {
        switch entry.phase {
        case .inSession:
            Text("Now")
                .font(Theme.Typo.footer.weight(.semibold))
                .foregroundStyle(.secondary)
        case .upcoming:
            Text("at \(ClassSession.format(entry.start))")
                .font(Theme.Typo.footer.weight(.medium))
                .foregroundStyle(.secondary)
        case .past:
            Text("Done")
                .font(Theme.Typo.detailMeta)
                .foregroundStyle(.tertiary)
        }
    }

    /// One phrase per class row for VoiceOver — mirrors `ClassBlock`'s label.
    private func classLabel(_ session: ClassSession, phase: ClassPhase) -> String {
        let state: String
        switch phase {
        case .inSession: state = "in session"
        case .upcoming: state = upcoming(for: session).countdown(now: now)
        case .past: state = "done"
        }
        return "\(session.subjectCode), \(session.description), \(session.timeLabel), \(state)"
    }

    private func phaseWord(_ phase: ClassPhase) -> String {
        switch phase {
        case .inSession: "now"
        case .upcoming: "upcoming"
        case .past: "done"
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
            "Nothing today",
            systemImage: "cup.and.saucer",
            description: Text("Enjoy the break — your week grid has the rest.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Notes

    /// The dot on a row that has a note — small enough to read as a mark, not a
    /// control.
    private var noteDot: some View {
        Circle()
            .fill(palette.accent)
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }

    /// A note's key: subject code for a class (stable across days), the event's
    /// block id for an event. Namespaced so the two can't collide.
    private func noteKey(_ entry: DayAgenda.AgendaEntry) -> String {
        if let session = entry.session { return "class:\(session.subjectCode)" }
        return "event:\(entry.id)"
    }

    /// The freeform day scratchpad's key — one per calendar day.
    private var dayKey: String {
        "day:\(now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
    }

    /// Title for the currently selected row's note, or nil if the selection no
    /// longer matches anything today (e.g. the day rolled over).
    private var selectedTitle: String? {
        guard let selectedKey else { return nil }
        return entries.first { noteKey($0) == selectedKey }?.title
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
