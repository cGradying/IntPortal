import SwiftUI

/// Today, read top to bottom: the day's timeline on the left, a rail of term
/// stats and upcoming syllabus dates on the right (spec 04's Today screen).
/// Notes and the day navigator now live in Notebook ("Today's note") — this
/// screen is display-only, a daily companion to the week grid.
///
/// Deliberately narrower than `AppState` — unlike `NotebookScreen`, which
/// needs the shared note-editor mirror fields, this screen only reads the
/// pieces it actually shows, so it's cheap to construct in a snapshot test
/// without a live `PortalController` or the Keychain. It reads `now` (the
/// shared minute clock, passed in rather than kept on a timer of its own) so
/// it re-renders on the minute the same way the menu bar and Notebook's own
/// timeline do — `AppShell` passes `appState.now` fresh on every redraw.
struct TodayScreen: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var quizzes: QuizStore
    @ObservedObject var syllabus: SyllabusStore
    let sessions: [ClassSession]
    /// The latest grades snapshot, for the rail's "Units" stat — `nil` before
    /// the first successful grades fetch.
    let grades: GradeReport?
    let now: Date
    /// "Start" on a gap's study suggestion. `AppShell` wires this to mark the
    /// deck pending on `QuizStore` and open Quizzes — see
    /// `QuizzesView.consumePendingDeck()`.
    var onStartDeck: (UUID) -> Void = { _ in }
    /// `ImageRenderer` (`Snapshot.render`) can't draw `ScrollView` content, so
    /// snapshot tests render with this off inside a fixed frame instead.
    var scrolls = true

    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    /// Flipped true on first appear so rows arrive once, on open, rather than
    /// re-staggering every minute the clock republishes.
    @State private var appeared = false

    private var nowMinutes: Int { NowLine.minutes(of: now) }
    private var weekStart: Date { Weekday.weekStart(containing: now) }

    private var agenda: DayAgenda {
        DayAgenda.make(
            sessions: sessions, now: now,
            isVacant: { session, date in preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant },
            time: { session, date in preferences.time(for: session, on: Weekday.weekStart(containing: date)) }
        )
    }

    /// Classes merged with today's custom calendar events, sorted and
    /// phased — the same seam `NotebookScreen` used to build this from
    /// (`DayAgenda.timeline`), now feeding this screen instead.
    private var entries: [DayAgenda.AgendaEntry] {
        DayAgenda.timeline(
            classes: sessions,
            events: calendar.todayBlocks(calendarIDs: preferences.visibleCalendarIDs, on: now),
            now: now,
            isVacant: { session, date in preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant },
            time: { session, date in preferences.time(for: session, on: Weekday.weekStart(containing: date)) }
        )
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { columns }.scrollIndicators(.hidden)
            } else {
                columns
            }
        }
        .onAppear { appeared = true }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            dayColumn
            rail
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
    }

    // MARK: Your day

    private var dayColumn: some View {
        Sheet(label: "Your day", meta: "It's \(ClassSession.format(nowMinutes))") {
            VStack(alignment: .leading, spacing: 0) {
                syllabusMarker
                if entries.isEmpty {
                    emptyDay
                } else {
                    timelineRows
                }
                tomorrowRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var timelineRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle().fill(palette.roles.line).frame(height: 1)
                }
                row(for: entry)
                    // Rows land in reading order on open, the same arrival the
                    // week grid uses. Reduce Motion → nil animation → instant.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(
                        Motion.arrival(reduced: reduceMotion)?.delay(Motion.stagger(index, reduced: reduceMotion)),
                        value: appeared
                    )

                // The free stretch before the next entry — the same ≥15-minute
                // threshold `DayAgenda.remainingFreeMinutes` counts by.
                if index < entries.count - 1 {
                    let next = entries[index + 1]
                    let free = next.start - entry.end
                    if free >= 15 {
                        gapRow(StudyGap(start: entry.end, end: next.start))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: DayAgenda.AgendaEntry) -> some View {
        if let session = entry.session {
            classRow(entry, session: session)
        } else {
            eventRow(entry)
        }
    }

    /// The time column every row (class, event, or gap) shares — start over
    /// end, in tabular Source Sans per the Legibility Rule (DESIGN.md): a
    /// time is exactly the kind of number Pixelify Sans misreads below 20pt.
    private func timeColumn(start: Int, end: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ClassSession.format(start)).font(typography.numeric(size: 14, weight: .semibold))
            Text("to \(ClassSession.format(end))").font(typography.detailMeta).foregroundStyle(palette.roles.ink3)
        }
        .frame(width: 74, alignment: .leading)
    }

    private func classRow(_ entry: DayAgenda.AgendaEntry, session: ClassSession) -> some View {
        let phase = entry.phase
        let color = preferences.color(for: session.subjectCode, in: palette)
        let status = preferences.status(for: session, on: weekStart)

        return HStack(alignment: .top, spacing: 14) {
            timeColumn(start: entry.start, end: entry.end)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.subjectCode).font(typography.blockCode).foregroundStyle(color)
                    if status == .online {
                        Image(systemName: "video.fill").font(.system(size: 10)).foregroundStyle(palette.roles.ink3)
                    }
                }
                Text(session.description).font(typography.footer).foregroundStyle(palette.roles.ink2).lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(tagText(phase: phase, entry: entry))
                    .font(typography.footer.weight(phase == .inSession ? .semibold : .regular))
                    .foregroundStyle(phase == .upcoming ? palette.roles.actionInk : palette.roles.ink2)
                if status != .vacant {
                    Stamp(kind: status == .online ? .online : .inPerson, subject: color, small: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(phase == .past ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(classLabel(session, phase: phase))
    }

    /// A calendar event — the user's own commitments folded into the same
    /// timeline. Neutral, no subject colour or stamp; those belong to classes.
    private func eventRow(_ entry: DayAgenda.AgendaEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            timeColumn(start: entry.start, end: entry.end)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(typography.blockCode).lineLimit(1)
                Text(entry.subtitle).font(typography.detailMeta).foregroundStyle(palette.roles.ink3)
            }

            Spacer(minLength: 8)

            Text(tagText(phase: entry.phase, entry: entry))
                .font(typography.footer.weight(entry.phase == .inSession ? .semibold : .regular))
                .foregroundStyle(entry.phase == .upcoming ? palette.roles.actionInk : palette.roles.ink2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(entry.phase == .past ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title), \(entry.subtitle), \(phaseWord(entry.phase))")
    }

    private func tagText(phase: ClassPhase, entry: DayAgenda.AgendaEntry) -> String {
        switch phase {
        case .past: "Done"
        case .inSession: "In session"
        case .upcoming: "in \(duration(entry.start - nowMinutes))"
        }
    }

    /// Mirrors `ClassBlock`'s own label shape (`Views/Blocks.swift`): code,
    /// description, time span, status.
    private func classLabel(_ session: ClassSession, phase: ClassPhase) -> String {
        "\(session.subjectCode), \(session.description), \(session.timeLabel), \(phaseWord(phase))"
    }

    private func phaseWord(_ phase: ClassPhase) -> String {
        switch phase {
        case .inSession: "in session"
        case .upcoming: "upcoming"
        case .past: "done"
        }
    }

    // MARK: Free time + "study in the gap" (spec 11 upgrade 1)

    /// Every ≥15-minute free stretch in today's timeline, in `StudyGap`'s
    /// minutes-from-midnight shape — what `GapSuggestion.make` reasons over.
    private var studyGaps: [StudyGap] {
        var gaps: [StudyGap] = []
        for i in entries.indices.dropLast() {
            let free = entries[i + 1].start - entries[i].end
            if free >= 15 { gaps.append(StudyGap(start: entries[i].end, end: entries[i + 1].start)) }
        }
        return gaps
    }

    /// The one gap `GapSuggestion.make` would pick — the row it lands the
    /// suggestion inside. Same selection rule (`now`'s gap, or the next one
    /// ahead), kept alongside separately so the row renderer can compare
    /// without re-deriving the suggestion's own gap.
    private var targetGap: StudyGap? {
        studyGaps.filter { $0.end > nowMinutes }.min { $0.start < $1.start }
    }

    /// Deck → nearest linked exam date, resolved via `ExamLink` (spec 11
    /// upgrade 2) so `GapSuggestion`'s tie-break ("nearer exam wins") has
    /// something to read.
    private var examDatesByDeck: [UUID: Date] {
        var result: [UUID: Date] = [:]
        for item in syllabus.allItems() where item.type == .exam {
            guard let examDate = item.date else { continue }
            let lectures = syllabus.items(for: item.subjectCode)
            for deck in ExamLink.decks(for: item, in: quizzes.decks, lectures: lectures) {
                result[deck.id] = min(result[deck.id] ?? .distantFuture, examDate)
            }
        }
        return result
    }

    private var gapSuggestion: GapSuggestion.Suggestion? {
        GapSuggestion.make(gaps: studyGaps, decks: quizzes.decks, now: now, examDates: examDatesByDeck)
    }

    /// A free stretch — sunk background, "Free · 6h" over a dithered gold
    /// bar, the gold "Now" line when `now` falls inside it, and the study
    /// suggestion when this is the gap `GapSuggestion` picked.
    private func gapRow(_ gap: StudyGap) -> some View {
        let containsNow = nowMinutes > gap.start && nowMinutes < gap.end
        let suggestion = gap == targetGap ? gapSuggestion : nil

        return HStack(alignment: .top, spacing: 14) {
            timeColumn(start: gap.start, end: gap.end)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Free · \(duration(gap.end - gap.start))")
                        .font(typography.numeric(size: 14, weight: .semibold))
                        .foregroundStyle(palette.roles.ink2)
                    DitherFill(color: palette.roles.gold, cell: 2, ramp: .flat(0.4))
                        // Canvas has no intrinsic size, so `maxHeight` alone
                        // collapses to nothing — an explicit height, then
                        // `maxWidth: .infinity` to fill the row.
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                if containsNow {
                    HStack(spacing: 8) {
                        Text("Now · \(ClassSession.format(nowMinutes))")
                            .font(typography.numeric(size: 12, weight: .semibold))
                            .foregroundStyle(palette.roles.goldInk)
                        Rectangle().fill(palette.roles.gold).frame(height: 2)
                    }
                }

                if let suggestion {
                    gapSuggestionBox(suggestion)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette.roles.sunk)
    }

    private func gapSuggestionBox(_ suggestion: GapSuggestion.Suggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Study in this gap: \(suggestion.deck.name)")
                    .font(typography.display(size: 14))
                    .foregroundStyle(palette.roles.ink)
                Text(suggestionDetail(suggestion))
                    .font(typography.detailMeta)
                    .foregroundStyle(palette.roles.ink3)
            }
            Spacer(minLength: 8)
            Button("Start") { onStartDeck(suggestion.deck.id) }
                .buttonStyle(PixelButtonStyle(kind: .primary, small: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.roles.sheet)
        .overlay(
            Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .foregroundStyle(palette.roles.line2)
        )
    }

    private func suggestionDetail(_ suggestion: GapSuggestion.Suggestion) -> String {
        var parts = [
            "\(suggestion.dueCount) card\(suggestion.dueCount == 1 ? "" : "s") due",
            "about \(suggestion.minutes) min of flashcards",
        ]
        if let examDate = suggestion.examDate { parts.append(Self.monthDay.string(from: examDate)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Empty day + tomorrow

    private var emptyDay: some View {
        Text("Nothing scheduled today.")
            .font(typography.footer)
            .foregroundStyle(palette.roles.ink2)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    private var tomorrowRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sunrise").foregroundStyle(palette.roles.ink3).accessibilityHidden(true)
            Text(tomorrowText).font(typography.footer).foregroundStyle(palette.roles.ink3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tomorrowText: String {
        guard let first = agenda.tomorrowFirst else { return "Tomorrow · nothing scheduled" }
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let start = preferences.time(for: first, on: Weekday.weekStart(containing: tomorrowDate)).start
        return "Tomorrow · \(first.subjectCode) at \(ClassSession.format(start))"
    }

    // MARK: Syllabus markers

    /// Today's syllabus items — an all-day marker line above the timed
    /// timeline, same reasoning `NotebookScreen.syllabusMarker` documented:
    /// a syllabus item usually has no class-time, just a date.
    @ViewBuilder private var syllabusMarker: some View {
        let items = syllabus.items(on: now)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.type.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.roles.ink3)
                        Text(item.topic).font(typography.footer).lineLimit(1)
                        Text(item.subjectCode).font(typography.detailMeta).foregroundStyle(palette.roles.ink3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: Helpers

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    // MARK: Rail — "This term" + "Due soon"

    private var rail: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            thisTermSheet
            dueSoonSheet
        }
        .frame(width: 280, alignment: .topLeading)
    }

    private var thisTermSheet: some View {
        Sheet(label: "This term", meta: "from your COR") {
            VStack(spacing: 0) {
                statRow("Subjects enrolled", "\(subjectsEnrolled)")
                statRow("Units", unitsLabel)
                statRow("Cards due today", "\(cardsDueToday)")
                statRow("Study streak", streakLabel, last: true)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func statRow(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(label).font(typography.footer).foregroundStyle(palette.roles.ink2)
            Spacer()
            Text(value).font(typography.numeric(size: 15, weight: .semibold)).foregroundStyle(palette.roles.ink)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(palette.roles.line).frame(height: 1).opacity(0.6) }
        }
    }

    private var subjectsEnrolled: Int { ClassSession.subjectCodes(in: sessions).count }

    private var unitsLabel: String {
        guard let grades else { return "—" }
        let total = grades.subjects.reduce(0.0) { $0 + $1.units }
        return total.rounded() == total ? String(Int(total)) : String(format: "%.1f", total)
    }

    private var cardsDueToday: Int {
        quizzes.decks.reduce(0) { $0 + $1.dueCards(now: now).count }
    }

    private var streakLabel: String {
        let streak = quizzes.stats.streak
        return "\(streak) day\(streak == 1 ? "" : "s")"
    }

    private var dueSoonSheet: some View {
        Sheet(label: "Due soon", meta: "from syllabi") {
            VStack(spacing: 0) {
                if dueSoonItems.isEmpty {
                    Text("Nothing due soon.")
                        .font(typography.footer)
                        .foregroundStyle(palette.roles.ink3)
                        .padding(Spacing.lg)
                } else {
                    ForEach(Array(dueSoonItems.enumerated()), id: \.element.id) { index, item in
                        DueSoonTile(item: item, now: now, last: index == dueSoonItems.count - 1)
                    }
                }
            }
        }
    }

    /// Upcoming syllabus items (today or later), earliest first, capped so
    /// the rail doesn't outgrow the day column.
    private var dueSoonItems: [SyllabusItem] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return syllabus.allItems()
            .filter { ($0.date ?? .distantPast) >= startOfToday }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            .prefix(4)
            .map { $0 }
    }
}
