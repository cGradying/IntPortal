import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Calendar export (Apple + Google), and the program's total units.
/// Everything about the schedule the user sets up once and rarely revisits.
struct SchedulePane: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var googleAuth: GoogleAuth
    let googleClient: GoogleCalendarClient
    let sessions: [ClassSession]

    @State private var exportResult: String?
    @State private var googleCalendars: [GoogleCalendar] = []
    @State private var googleBusy = false
    @State private var googleResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            calendarSection
            googleSection

            SettingsSection(
                title: "Grades",
                footer: "Your program's total required units, for the completed-units progress on the Grades trend. SIS doesn't publish it."
            ) {
                SettingsRow(label: "Program total units") {
                    HStack(spacing: 8) {
                        Text(preferences.programTotalUnits == 0 ? "Not set" : "\(preferences.programTotalUnits)")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $preferences.programTotalUnits, in: 0...400, step: 3).labelsHidden()
                    }
                }
            }

            SettingsResetButton {
                preferences.exportCalendarID = ""
                preferences.onlineExportCalendarID = ""
                preferences.googleClientID = ""
                preferences.googleCalendarID = ""
                preferences.termEndDate = Preferences.defaultTermEnd()
                preferences.programTotalUnits = 0
                preferences.visibleCalendarIDs = []
            }

            SettingsTechnicalSection(rows: [
                ("Export calendar", preferences.exportCalendarID.isEmpty ? "none" : preferences.exportCalendarID),
                ("Online calendar", preferences.onlineExportCalendarID.isEmpty ? "none" : preferences.onlineExportCalendarID),
                ("Google calendar", preferences.googleCalendarID.isEmpty ? "none" : preferences.googleCalendarID),
                ("Cached sessions", "\(sessions.count)"),
            ])
        }
        .task(id: googleAuth.isConnected) {
            if googleAuth.isConnected { await loadGoogleCalendars() }
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        SettingsSection(title: "Calendar", footer: calendarFooter) {
            switch calendar.access {
            case .notDetermined:
                SettingsRow(label: "Calendar.app") {
                    Button("Connect…") { Task { await calendar.requestAccess() } }
                        .buttonStyle(.pixelSmall)
                }

            case .denied:
                Label(
                    "Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

            case .granted:
                if calendar.calendars.isEmpty {
                    Text("No calendars found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.calendars) { info in
                        SettingsRow(label: info.title) {
                            HStack(spacing: 6) {
                                Circle().fill(info.color).frame(width: 8, height: 8)
                                Text(info.source).font(.caption2).foregroundStyle(.secondary)
                                Toggle("", isOn: Binding(
                                    get: { preferences.visibleCalendarIDs.contains(info.id) },
                                    set: { preferences.setCalendar(info.id, visible: $0) }
                                )).labelsHidden().toggleStyle(.switch)
                            }
                        }
                    }
                }

                if calendar.writableCalendars.isEmpty {
                    Text("None of your calendars can be edited, so classes can't be exported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SettingsRow(label: "In-person classes to") {
                        Picker("", selection: $preferences.exportCalendarID) {
                            Text("Choose a calendar…").tag("")
                            ForEach(calendar.writableCalendars) { info in
                                Text("\(info.title) · \(info.source)").tag(info.id)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .trailing)
                    }

                    SettingsRow(label: "Online classes to") {
                        Picker("", selection: $preferences.onlineExportCalendarID) {
                            Text("Same as in-person").tag("")
                            ForEach(calendar.writableCalendars) { info in
                                Text("\(info.title) · \(info.source)").tag(info.id)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .trailing)
                        .disabled(preferences.exportCalendarID.isEmpty)
                    }

                    SettingsRow(label: "Repeat until") {
                        DatePicker("", selection: $preferences.termEndDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    SettingsRow(label: "Your classes") {
                        Button("Add to Calendar…", action: exportClasses)
                            .buttonStyle(.pixelSmall)
                            .disabled(sessions.isEmpty || preferences.exportCalendarID.isEmpty)
                    }
                }
            }

            SettingsRow(label: "Google & other accounts") {
                Button("Open Internet Accounts…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.pixelSmall)
            }

            SettingsRow(label: "Schedule file") {
                Button("Export .ics…", action: exportICS)
                    .buttonStyle(.pixelSmall)
                    .disabled(sessions.isEmpty)
            }

            if let result = exportResult {
                Text(result).font(.caption2).foregroundStyle(.secondary)
            }
            if let error = calendar.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var calendarFooter: String {
        switch calendar.access {
        case .granted:
            """
            Ticked calendars appear alongside your classes in the week grid. \
            Adding your classes writes them as weekly repeats into the calendars you choose, \
            stopping on the date above; running it again replaces the ones this app added \
            and leaves your own events alone. Online classes can go to their own calendar — \
            pick one under "Online classes to" — otherwise they land with the rest, labelled \
            Online. Classes marked vacant for the term are left off; a class vacant for a single \
            week loses just that date. After the first export, status changes sync automatically. \
            Classes added this way stay hidden here so they don't show up twice — they're still \
            in Calendar.app and on your other devices. To use a Google calendar, add the account \
            in System Settings › Internet Accounts (with Calendars on) and it appears above.
            """
        default:
            "Nothing from your calendar is shown until you connect and pick which calendars to include. Google calendars appear here once the account is added in System Settings › Internet Accounts."
        }
    }

    @ViewBuilder
    private var googleSection: some View {
        SettingsSection(
            title: "Google Calendar (direct)",
            footer: """
            Writes classes straight to Google, bypassing Apple Calendar (whose \
            Google sync is unreliable for repeating events). One-time setup: at \
            console.cloud.google.com create a project, enable the Google Calendar \
            API, add yourself as a Test user on the OAuth consent screen, then \
            create an OAuth client ID of type iOS with bundle ID \
            com.cgradying.pupsisportal and paste its Client ID above. While the \
            consent screen stays in testing, Google asks you to reconnect about \
            once a week.
            """
        ) {
            if !googleAuth.isConnected {
                SettingsRow(label: "OAuth client ID") {
                    TextField("", text: $preferences.googleClientID)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: 220, alignment: .trailing)
                }
                SettingsRow(label: "Google account") {
                    Button("Connect Google") { connectGoogle() }
                        .buttonStyle(.pixelSmall)
                        .disabled(preferences.googleClientID.trimmingCharacters(in: .whitespaces).isEmpty || googleBusy)
                }
            } else {
                SettingsRow(label: "Export to") {
                    Picker("", selection: $preferences.googleCalendarID) {
                        Text("Choose a calendar…").tag("")
                        ForEach(googleCalendars) { cal in
                            Text(cal.summary).tag(cal.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .trailing)
                }
                SettingsRow(label: "Your classes") {
                    Button("Export to Google", action: exportToGoogle)
                        .buttonStyle(.pixelSmall)
                        .disabled(sessions.isEmpty || preferences.googleCalendarID.isEmpty || googleBusy)
                }
                Button("Disconnect Google", role: .destructive) {
                    googleAuth.disconnect()
                    googleCalendars = []
                    googleResult = nil
                }
                .buttonStyle(.borderless).controlSize(.small).font(.caption)
            }

            if googleBusy {
                HStack { ProgressView().controlSize(.small); Text("Working…").font(.caption2).foregroundStyle(.secondary) }
            }
            if let googleResult {
                Text(googleResult).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func connectGoogle() {
        googleBusy = true
        googleResult = nil
        Task {
            defer { googleBusy = false }
            do {
                try await googleAuth.connect()
                await loadGoogleCalendars()
            } catch {
                googleResult = error.localizedDescription
            }
        }
    }

    private func loadGoogleCalendars() async {
        do {
            googleCalendars = try await googleClient.listCalendars()
        } catch {
            googleResult = error.localizedDescription
        }
    }

    private func exportToGoogle() {
        googleBusy = true
        googleResult = nil
        Task {
            defer { googleBusy = false }
            do {
                googleResult = try await googleClient.exportClasses(
                    sessions,
                    weekStart: Weekday.weekStart(containing: .now),
                    until: preferences.termEndDate,
                    toCalendarID: preferences.googleCalendarID,
                    status: { preferences.termStatus(for: $0) },
                    time: { preferences.time(for: $0, on: $1) }
                )
            } catch {
                googleResult = error.localizedDescription
            }
        }
    }

    private func exportICS() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PUPSIS-Schedule.ics"
        if let ics = UTType(filenameExtension: "ics") {
            panel.allowedContentTypes = [ics]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = ICSExporter.ics(
            for: sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            status: { preferences.termStatus(for: $0) },
            time: { preferences.time(for: $0, on: $1) }
        )
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportResult = "Saved schedule to “\(url.lastPathComponent)”."
        } catch {
            exportResult = error.localizedDescription
        }
    }

    private func exportClasses() {
        exportResult = calendar.exportClasses(
            sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            toCalendarID: preferences.exportCalendarID,
            onlineCalendarID: preferences.onlineExportCalendarID.isEmpty ? nil : preferences.onlineExportCalendarID,
            status: { preferences.status(for: $0, on: $1) },
            time: { preferences.time(for: $0, on: $1) }
        )
    }
}
