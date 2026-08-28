import SwiftUI

/// The syllabus, per subject, in either of two readings — a table or a
/// timeline (wayfinder ticket #14). Native SwiftUI reading `SyllabusStore`
/// directly, not the notes-editor's `pupdb` widget: `pupdb` lives inside a
/// note's markdown, and syllabus items are a native Swift store, not note
/// text — routing one through the other would mean syncing two sources of
/// truth for no real benefit. This borrows pupdb's *visual language* (typed
/// columns, colored pills) rather than its code.
///
/// Two entry points render this same view: Notebook's third tab (beside
/// Vault/Quizzes) and a section below the Schedule screen's week grid.
struct SyllabusView: View {
    @ObservedObject var syllabus: SyllabusStore
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @State private var mode: Mode = .timeline

    enum Mode: String, CaseIterable, Identifiable {
        case table, timeline
        var id: String { rawValue }
        var symbol: String { self == .table ? "tablecells" : "list.bullet.rectangle" }
        var label: String { self == .table ? "Table" : "Timeline" }
    }

    private var bySubject: [(subject: String, items: [SyllabusItem])] {
        Dictionary(grouping: syllabus.allItems(), by: \.subjectCode)
            .map { (subject: $0.key, items: $0.value.sorted(by: Self.chronological)) }
            .sorted { $0.subject < $1.subject }
    }

    /// Dated items first (earliest to latest), undated items after — a
    /// missing date shouldn't sort as "the beginning of time".
    private static func chronological(_ a: SyllabusItem, _ b: SyllabusItem) -> Bool {
        switch (a.date, b.date) {
        case let (l?, r?): return l < r
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private func weekOf(_ date: Date) -> Date { Weekday.weekStart(containing: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Syllabus").font(typography.screenTitle)
                Spacer()
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Image(systemName: m.symbol).accessibilityLabel(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }

            if bySubject.isEmpty {
                emptyState
            } else {
                ForEach(bySubject, id: \.subject) { group in
                    subjectSection(group.subject, group.items)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Nothing creates a syllabus item yet — that's ticket #15 (import +
    // AI generation). This view is built ahead of its own data source, same
    // as #13 was; verified against hand-seeded SyllabusStore data.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No syllabus items yet")
                .font(typography.detailBody)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func subjectSection(_ subject: String, _ items: [SyllabusItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subject).font(typography.detailTitle)
            switch mode {
            case .table: tableView(items)
            case .timeline: timelineView(items)
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 14)
    }

    // MARK: Table

    private func tableView(_ items: [SyllabusItem]) -> some View {
        Table(items) {
            TableColumn("Wk") { item in Text(item.week.map(String.init) ?? "—") }
                .width(32)
            TableColumn("Topic") { item in Text(item.topic).lineLimit(1) }
            TableColumn("Date") { item in
                Text(item.date.map { Self.dateFormatter.string(from: $0) } ?? "—")
            }
            .width(70)
            TableColumn("Type") { item in typePill(item.type) }
                .width(84)
            TableColumn("Status") { item in statusPill(item) }
                .width(84)
        }
        // Table has no natural content height on macOS — without an
        // explicit floor it renders at whatever the scroll container hands
        // it, which was 0pt for `n` rows the first time this ran headless of
        // a fixed-height parent.
        .frame(minHeight: CGFloat(items.count) * 28 + 34, maxHeight: CGFloat(items.count) * 28 + 34)
    }

    private func typePill(_ type: SyllabusItemType) -> some View {
        Label(type.label, systemImage: type.symbol)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(palette.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(palette.accent)
    }

    private func statusPill(_ item: SyllabusItem) -> some View {
        let status = item.status(now: Date(), weekOf: weekOf)
        return Text(label(for: status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color(for: status).opacity(status == .upcoming ? 0.12 : 0.18), in: Capsule())
            .foregroundStyle(status == .upcoming ? .secondary : color(for: status))
    }

    // MARK: Timeline

    private func timelineView(_ items: [SyllabusItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    statusRing(item)
                    if let week = item.week {
                        Text("Wk\(week)")
                            .font(typography.detailMeta)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                    }
                    Image(systemName: item.type.symbol)
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                    Text(item.topic).font(typography.footer).lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = item.date {
                        Text(Self.dateFormatter.string(from: date))
                            .font(typography.detailMeta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Hollow outline = upcoming, solid accent outline = this week, filled =
    /// done — three states, one color, matching the week header's own "just
    /// a dot" restraint (`WeekGrid.header`) rather than inventing a second
    /// color language for the same done/ongoing/upcoming idea.
    private func statusRing(_ item: SyllabusItem) -> some View {
        let status = item.status(now: Date(), weekOf: weekOf)
        return Circle()
            .strokeBorder(status == .upcoming ? Color.secondary.opacity(0.35) : palette.accent, lineWidth: 1.5)
            .background(Circle().fill(status == .done ? palette.accent : Color.clear))
            .frame(width: 10, height: 10)
    }

    private func color(for status: SyllabusStatus) -> Color {
        status == .upcoming ? .secondary : palette.accent
    }

    private func label(for status: SyllabusStatus) -> String {
        switch status {
        case .done: "Done"
        case .ongoing: "This week"
        case .upcoming: "Upcoming"
        }
    }
}
