import SwiftUI

struct ScheduleView: View {
    let entries: [ScheduleEntry]

    var body: some View {
        if entries.isEmpty {
            EmptyStateView(title: "No schedule loaded yet", systemImage: "calendar")
        } else {
            Table(entries) {
                TableColumn("Code", value: \.subjectCode)
                TableColumn("Description", value: \.description)
                TableColumn("Units", value: \.unit)
                TableColumn("Schedule", value: \.schedule)
            }
        }
    }
}
