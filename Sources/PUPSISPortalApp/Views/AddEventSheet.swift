import SwiftUI

/// Creates an event straight in Calendar.app. The app stores nothing itself —
/// it writes, then reads the week back, so there's one source of truth.
struct AddEventSheet: View {
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var preferences: Preferences
    /// Pre-filled from the slot that was double-clicked.
    let initialDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var title = ""
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var calendarID = ""

    init(calendar: CalendarBridge, preferences: Preferences, initialDate: Date) {
        self.calendar = calendar
        self.preferences = preferences
        self.initialDate = initialDate

        let hour = Calendar.current.dateComponents([.hour], from: initialDate).hour ?? 9
        let day = Calendar.current.startOfDay(for: initialDate)
        let from = Calendar.current.date(byAdding: .hour, value: hour, to: day) ?? initialDate

        _date = State(initialValue: day)
        _start = State(initialValue: from)
        _end = State(initialValue: Calendar.current.date(byAdding: .hour, value: 1, to: from) ?? from)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Event")
                .font(Theme.Typo.screenTitle)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Form {
                TextField("Title", text: $title)

                DatePicker("Date", selection: $date, displayedComponents: .date)
                DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)

                Picker("Calendar", selection: $calendarID) {
                    ForEach(calendar.calendars) { info in
                        Text(info.title).tag(info.id)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                if !isValid {
                    Text("End time must be after the start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!isValid || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 420)
        .tint(palette.accent)
        .background(palette.canvasWash)
        .onAppear {
            // Default to a calendar already shown in the grid, so a new event
            // doesn't vanish into one that isn't ticked.
            calendarID = calendar.calendars.first { preferences.visibleCalendarIDs.contains($0.id) }?.id
                ?? calendar.calendars.first?.id
                ?? ""
        }
    }

    private var isValid: Bool {
        NowLine.minutes(of: end) > NowLine.minutes(of: start)
    }

    private func add() {
        calendar.add(
            title: title.trimmingCharacters(in: .whitespaces),
            on: date,
            start: NowLine.minutes(of: start),
            end: NowLine.minutes(of: end),
            calendarID: calendarID
        )
        // Make sure it's actually visible, or "Add" looks like it did nothing.
        preferences.setCalendar(calendarID, visible: true)
        dismiss()
    }
}
