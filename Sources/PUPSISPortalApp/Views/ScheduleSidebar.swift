import AppKit
import SwiftUI

/// The Schedule screen's sidebar: status (what used to be the bottom bar),
/// syllabus tasks, and per-subject files/links. Mounted by `CalendarView`
/// the same way `AgendaView` mounts its own notebook sidebar — a resize
/// handle plus a fixed-width column, both reading `Preferences`.
struct ScheduleSidebar: View {
    let lastUpdated: Date?
    let refreshError: String?
    let update: String?
    let onCheckForUpdates: () -> Void
    let sessions: [ClassSession]
    let isVacant: (ClassSession, Date) -> Bool
    let time: (ClassSession, Date) -> (Int, Int)
    let tint: (ClassSession) -> Color
    let onRetry: () -> Void
    let onPrint: () -> Void
    @ObservedObject var preferences: Preferences
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    private var subjectCodes: [String] { ClassSession.subjectCodes(in: sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                Divider()
                syllabusSection
                Divider()
                filesSection
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    // MARK: Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NextClassBanner(sessions: sessions, isVacant: isVacant, time: time, tint: tint)

            if let refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Text(staleness)
                .font(typography.footer)
                .foregroundStyle(.secondary)

            if let update {
                Button(action: onCheckForUpdates) {
                    Label("v\(update) available", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .help("Installs the update in place, then relaunches.")
            }

            HStack {
                Button("Print…", action: onPrint)
                    .glassButton()
                    .controlSize(.small)
                Button(refreshError == nil ? "Refresh" : "Try again", action: onRetry)
                    .glassButton()
                    .tint(palette.accent)
                    .controlSize(.small)
            }
        }
    }

    private var staleness: String {
        guard let lastUpdated else { return "Never updated" }
        guard Date().timeIntervalSince(lastUpdated) >= 60 else { return "Updated just now" }
        return "Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
    }

    // MARK: Syllabus tasks

    private var syllabusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Syllabus").font(typography.detailTitle)

            if subjectCodes.isEmpty {
                Text("Subjects appear here once your schedule loads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subjectCodes, id: \.self) { code in
                    SubjectTaskGroup(subjectCode: code, preferences: preferences)
                }
            }
        }
    }

    // MARK: Files/links

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files & Links").font(typography.detailTitle)

            let linked = subjectCodes.filter { code in
                !(preferences.classInfo[code]?.link.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
            }
            if linked.isEmpty {
                Text("Set a subject's link from its class block — \"Apply to every block\" — and it shows here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked, id: \.self) { code in
                    SubjectLinkRow(subjectCode: code, preferences: preferences)
                }
            }
        }
    }
}

/// "Next class in N minutes" — the single most useful glance in the app.
///
/// Ticks from its own `TimelineView` rather than a timer, and starts on the
/// next :00 so the countdown changes when the minute does. Same mechanism
/// `NowLine` uses one level up in the grid.
private struct NextClassBanner: View {
    let sessions: [ClassSession]
    let isVacant: (ClassSession, Date) -> Bool
    let time: (ClassSession, Date) -> (Int, Int)
    let tint: (ClassSession) -> Color

    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: NowLine.nextMinute, by: 60)) { context in
            if let upcoming = NextClass.next(in: sessions, at: context.date, isVacant: isVacant, time: time) {
                let color = tint(upcoming.session)

                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)

                    Text(upcoming.session.subjectCode)
                        .font(typography.blockCode)

                    Text(upcoming.countdown(now: context.date))
                        .foregroundStyle(.secondary)
                }
                .font(typography.footer)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .glassTintedCapsule(color.opacity(0.18))
                .help("\(upcoming.session.description) · \(upcoming.session.timeLabel)")
                .accessibilityElement(children: .combine)
                // Only the subject changing is worth animating; the countdown
                // ticking every minute would strobe the whole lozenge.
                .animation(Motion.drift(reduced: reduceMotion), value: upcoming.session.id)
            }
        }
    }
}

/// One subject's task list — add row, then its own tasks with a done
/// checkbox and delete. Reads/writes `Preferences.subjectTasks` directly
/// (filtered client-side; the store itself stays a flat array — see
/// `SubjectTask`'s doc comment).
private struct SubjectTaskGroup: View {
    let subjectCode: String
    @ObservedObject var preferences: Preferences
    @State private var newTitle = ""
    @State private var newDue: Date?
    @State private var showingDatePicker = false

    private var tasks: [SubjectTask] {
        preferences.subjectTasks.filter { $0.subjectCode == subjectCode }
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tasks) { task in
                    HStack(spacing: 6) {
                        Button { preferences.toggleTask(task.id) } label: {
                            Image(systemName: task.done ? "checkmark.square.fill" : "square")
                        }
                        .buttonStyle(.plain)

                        Text(task.title)
                            .font(.caption)
                            .strikethrough(task.done)
                            .foregroundStyle(task.done ? .secondary : .primary)

                        if let due = task.dueDate {
                            Text(due.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button { preferences.deleteTask(task.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    TextField("Add task…", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onSubmit(addTask)
                    Button {
                        showingDatePicker.toggle()
                    } label: {
                        Image(systemName: "calendar").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(newDue == nil ? .secondary : .primary)
                    .popover(isPresented: $showingDatePicker) {
                        DatePicker(
                            "Due", selection: Binding(get: { newDue ?? .now }, set: { newDue = $0 }),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding(12)
                        .labelsHidden()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(subjectCode).font(.caption.weight(.semibold))
        }
    }

    private func addTask() {
        preferences.addTask(newTitle, for: subjectCode, due: newDue)
        newTitle = ""
        newDue = nil
    }
}

/// One subject's saved link, opened the same way `ClassBlock`'s own "Join"
/// button does — same `scheme != nil` guard (`Blocks.swift`).
private struct SubjectLinkRow: View {
    let subjectCode: String
    @ObservedObject var preferences: Preferences

    private var url: URL? {
        let link = preferences.classInfo[subjectCode]?.link.trimmingCharacters(in: .whitespaces) ?? ""
        guard !link.isEmpty, let url = URL(string: link), url.scheme != nil else { return nil }
        return url
    }

    var body: some View {
        if let url {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(subjectCode, systemImage: "link")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
}
