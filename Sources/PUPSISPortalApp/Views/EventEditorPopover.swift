import SwiftUI

/// Create and edit in one view, anchored beside the block it belongs to.
///
/// Replaces the centred sheet: a sheet pulls focus out of the grid on every
/// create, which is the opposite of what a calendar needs. Here the eye never
/// leaves the block being drawn.
struct EventEditorPopover: View {
    @State var draft: EventSnapshot
    let calendars: [CalendarInfo]
    /// Nil when creating; set when editing an existing block.
    let existing: DayBlock?
    let isRecurring: Bool

    let onCommit: (EventSnapshot) -> Void
    let onDelete: (() -> Void)?
    let onDuplicate: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @FocusState private var titleFocused: Bool

    /// Quick lengths, so the common case never opens a time picker.
    private let durations = [30, 60, 90, 120, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            title
            Divider()
            days
            length
            repeatToggle
            calendarPicker
            Divider()
            details
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 320)
        .tint(palette.accent)
        .onAppear { titleFocused = existing == nil }
    }

    // MARK: Sections

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Event title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(typography.detailTitle)
                .focused($titleFocused)
                .onSubmit(commit)

            HStack(spacing: 5) {
                Text(draft.summary)
                if isRecurring {
                    Image(systemName: "repeat")
                }
            }
            .font(typography.detailMeta)
            .foregroundStyle(.secondary)
        }
    }

    /// Day pills, so the repeat can be changed without re-dragging the grid.
    private var days: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.allCases) { day in
                let on = draft.repeatDays.contains(day)

                Button(String(day.short.prefix(1))) { toggle(day) }
                    .buttonStyle(.plain)
                    .font(typography.dayName)
                    .foregroundStyle(on ? .white : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(on ? palette.accent : palette.accent.opacity(0.08)))
                    .help(day.short)
            }
        }
    }

    private var length: some View {
        HStack(spacing: 6) {
            ForEach(durations, id: \.self) { minutes in
                let on = draft.end - draft.start == minutes

                Button(label(for: minutes)) { draft.end = draft.start + minutes }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(palette.accent.opacity(on ? 0.22 : 0.08)))
            }
        }
    }

    /// Off by default. A drag across three days should put three blocks in
    /// this week, not something that returns every week until the term ends.
    private var repeatToggle: some View {
        Toggle(isOn: $draft.repeatsWeekly) {
            Text(draft.repeatsWeekly ? "Repeats weekly until term ends" : "Just this week")
                .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    @ViewBuilder
    private var calendarPicker: some View {
        // Only worth showing when there's an actual choice to make.
        if calendars.count > 1 {
            Picker("Calendar", selection: $draft.calendarID) {
                ForEach(calendars) { info in
                    Text(info.title).tag(info.id)
                }
            }
            .labelsHidden()
        }
    }

    /// Both optional — same convention as a class's own note/link editor
    /// (`Blocks.swift`), just for a custom calendar event instead of a
    /// scraped class.
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Description", text: $draft.note, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
            TextField("Link", text: $draft.link)
                .textFieldStyle(.plain)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let onDelete {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            if let onDuplicate {
                Button("Duplicate") {
                    onDuplicate()
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(existing == nil ? "Add" : "Save", action: commit)
                .keyboardShortcut(.defaultAction)
                .glassProminentButton()
                .disabled(!canCommit)
        }
    }

    // MARK: Detail

    private var canCommit: Bool {
        draft.end > draft.start
            && !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.calendarID.isEmpty
            && !draft.repeatDays.isEmpty
    }

    private func toggle(_ day: Weekday) {
        if let index = draft.repeatDays.firstIndex(of: day) {
            // Never leave an event with no day at all.
            guard draft.repeatDays.count > 1 else { return }
            draft.repeatDays.remove(at: index)
        } else {
            draft.repeatDays.append(day)
            draft.repeatDays.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func label(for minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private func commit() {
        guard canCommit else { return }
        var committed = draft
        committed.title = draft.title.trimmingCharacters(in: .whitespaces)
        onCommit(committed)
        dismiss()
    }
}
