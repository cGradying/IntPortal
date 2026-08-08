import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var googleAuth: GoogleAuth
    @ObservedObject fileprivate var notifier = Notifier.shared
    @Environment(\.palette) private var palette
    @State fileprivate var exportResult: String?
    @State fileprivate var googleCalendars: [GoogleCalendar] = []
    @State fileprivate var googleBusy = false
    @State fileprivate var googleResult: String?
    /// Mirrors the OS login-item status; re-read after every toggle so it can't
    /// drift from System Settings.
    @State fileprivate var launchAtLogin = LoginItem.isEnabled

    /// Subjects the user can actually recolor: whatever is on screen right now.
    private var subjectCodes: [String] {
        Array(Set(appState.portal.sessions.map(\.subjectCode))).sorted()
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.theme) {
                    ForEach(ThemeChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                if subjectCodes.isEmpty {
                    Text("Subjects appear here once your schedule loads.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subjectCodes, id: \.self) { code in
                        SubjectColorRow(code: code, preferences: preferences, palette: palette)
                    }
                }
            } header: {
                Text("Subject Colors")
            } footer: {
                Text("Colors are remembered per subject code and survive a refresh.")
                    .foregroundStyle(.secondary)
            }

            calendarSection

            googleSection

            Section {
                Picker("Style", selection: $preferences.notesStyle) {
                    ForEach(NotesStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Today Notes")
            } footer: {
                Text("Sidebar keeps a plain notes column beside Today. Popup opens a Markdown note (# headings, - bullets, - [ ] tasks) from a class, event, or the Notes button.")
                    .foregroundStyle(.secondary)
            }

            notificationSection

            Section {
                Stepper(value: $preferences.programTotalUnits, in: 0...400, step: 3) {
                    LabeledContent("Program total units") {
                        Text(preferences.programTotalUnits == 0
                             ? "Not set"
                             : "\(preferences.programTotalUnits)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Grades")
            } footer: {
                Text("Your program's total required units, for the completed-units progress on the Grades trend. SIS doesn't publish it.")
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                LabeledContent("Last updated") {
                    Text(appState.portal.lastUpdated.map {
                        $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "Never")
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Refresh Schedule") {
                        Task { await appState.portal.loadSchedule() }
                    }
                    Button("Edit Credentials") { appState.isEditing = true }
                    Spacer()
                    Button("Sign Out", role: .destructive) { appState.signOut() }
                }
            }
        }
        .formStyle(.grouped)
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.canvasWash.ignoresSafeArea())
        .navigationTitle("Settings")
        .task { await notifier.refreshAuthorization() }
        .task(id: googleAuth.isConnected) {
            if googleAuth.isConnected { await loadGoogleCalendars() }
        }
    }
}

private extension SettingsView {
    @ViewBuilder
    var notificationSection: some View {
        Section {
            Toggle("Remind me before class", isOn: Binding(
                // Not a plain binding: turning it on is what asks for
                // authorization, and a toggle that stays on while nothing can
                // fire is worse than one that refuses.
                get: { preferences.notificationsEnabled },
                set: { wants in
                    guard wants else {
                        preferences.notificationsEnabled = false
                        syncNotifications()
                        return
                    }
                    Task {
                        preferences.notificationsEnabled = await notifier.requestAuthorization()
                        syncNotifications()
                    }
                }
            ))

            Picker("How early", selection: $preferences.notificationLeadMinutes) {
                ForEach(Preferences.leadOptions, id: \.self) { minutes in
                    Text("\(minutes) minutes before").tag(minutes)
                }
            }
            .disabled(!preferences.notificationsEnabled)
            // Rebuilt from here, not only from the calendar: that view isn't
            // alive while this pane is on screen, so it can't do it for us.
            .onChange(of: preferences.notificationLeadMinutes) { syncNotifications() }

            if notifier.authorization == .denied {
                LabeledContent("Notifications are turned off for this app") {
                    Button("Open System Settings…") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                        else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, wants in
                    LoginItem.setEnabled(wants)
                    // Reflect what actually took effect, in case registration failed.
                    launchAtLogin = LoginItem.isEnabled
                }
        } header: {
            Text("Notifications")
        } footer: {
            Text("""
            One reminder per class meeting, repeating weekly. Meetings you've \
            marked vacant are skipped. Reminders fire only while PUPSISPortal is \
            running — turn on Start at login so it's always there to fire them, \
            even after a restart.
            """)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var calendarSection: some View {
        Section {
            switch calendar.access {
            case .notDetermined:
                LabeledContent("Calendar.app") {
                    Button("Connect…") {
                        Task { await calendar.requestAccess() }
                    }
                }

            case .denied:
                Label(
                    "Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)

            case .granted:
                if calendar.calendars.isEmpty {
                    Text("No calendars found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.calendars) { info in
                        Toggle(isOn: Binding(
                            get: { preferences.visibleCalendarIDs.contains(info.id) },
                            set: { preferences.setCalendar(info.id, visible: $0) }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(info.title)
                                    // The account, so a Google calendar is
                                    // identifiable next to an iCloud one.
                                    Text(info.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Circle().fill(info.color).frame(width: 10, height: 10)
                            }
                        }
                    }
                }

                if calendar.writableCalendars.isEmpty {
                    Text("None of your calendars can be edited, so classes can't be exported.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("In-person classes to", selection: $preferences.exportCalendarID) {
                        Text("Choose a calendar…").tag("")
                        ForEach(calendar.writableCalendars) { info in
                            Text("\(info.title) · \(info.source)").tag(info.id)
                        }
                    }

                    // Route online classes to their own calendar — a separate
                    // "label" in Apple/Google Calendar — or leave them with the rest.
                    Picker("Online classes to", selection: $preferences.onlineExportCalendarID) {
                        Text("Same as in-person").tag("")
                        ForEach(calendar.writableCalendars) { info in
                            Text("\(info.title) · \(info.source)").tag(info.id)
                        }
                    }
                    .disabled(preferences.exportCalendarID.isEmpty)

                    DatePicker(
                        "Repeat until",
                        selection: $preferences.termEndDate,
                        displayedComponents: .date
                    )

                    LabeledContent("Your classes") {
                        Button("Add to Calendar…", action: exportClasses)
                            .disabled(appState.portal.sessions.isEmpty
                                      || preferences.exportCalendarID.isEmpty)
                    }
                }
            }

            // Google (and any other) calendars flow into the app through
            // EventKit once the account is added to macOS — this is the way in.
            LabeledContent("Google & other accounts") {
                Button("Open Internet Accounts…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
            }

            // A plain file, so the schedule can go anywhere — Google Calendar's
            // web import, a phone — without granting calendar access at all.
            LabeledContent("Schedule file") {
                Button("Export .ics…", action: exportICS)
                    .disabled(appState.portal.sessions.isEmpty)
            }

            if let result = exportResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = calendar.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text(calendarFooter)
                .foregroundStyle(.secondary)
        }
    }

    var calendarFooter: String {
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
    var googleSection: some View {
        Section {
            if !googleAuth.isConnected {
                TextField("OAuth client ID", text: $preferences.googleClientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Google account") {
                    Button("Connect Google") { connectGoogle() }
                        .disabled(preferences.googleClientID.trimmingCharacters(in: .whitespaces).isEmpty || googleBusy)
                }
            } else {
                Picker("Export to", selection: $preferences.googleCalendarID) {
                    Text("Choose a calendar…").tag("")
                    ForEach(googleCalendars) { cal in
                        Text(cal.summary).tag(cal.id)
                    }
                }

                LabeledContent("Your classes") {
                    Button("Export to Google", action: exportToGoogle)
                        .disabled(appState.portal.sessions.isEmpty
                                  || preferences.googleCalendarID.isEmpty
                                  || googleBusy)
                }

                Button("Disconnect Google", role: .destructive) {
                    googleAuth.disconnect()
                    googleCalendars = []
                    googleResult = nil
                }
            }

            if googleBusy {
                HStack { ProgressView().controlSize(.small); Text("Working…").foregroundStyle(.secondary) }
            }
            if let googleResult {
                Text(googleResult).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Google Calendar (direct)")
        } footer: {
            Text("""
            Writes classes straight to Google, bypassing Apple Calendar (whose \
            Google sync is unreliable for repeating events). One-time setup: at \
            console.cloud.google.com create a project, enable the Google Calendar \
            API, add yourself as a Test user on the OAuth consent screen, then \
            create an OAuth client ID of type iOS with bundle ID \
            com.cgradying.pupsisportal and paste its Client ID above. While the \
            consent screen stays in testing, Google asks you to reconnect about \
            once a week.
            """)
            .foregroundStyle(.secondary)
        }
    }

    func connectGoogle() {
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

    func loadGoogleCalendars() async {
        do {
            googleCalendars = try await appState.googleClient.listCalendars()
        } catch {
            googleResult = error.localizedDescription
        }
    }

    func exportToGoogle() {
        googleBusy = true
        googleResult = nil
        Task {
            defer { googleBusy = false }
            do {
                googleResult = try await appState.googleClient.exportClasses(
                    appState.portal.sessions,
                    weekStart: Weekday.weekStart(containing: .now),
                    until: preferences.termEndDate,
                    toCalendarID: preferences.googleCalendarID,
                    status: { preferences.termStatus(for: $0) }
                )
            } catch {
                googleResult = error.localizedDescription
            }
        }
    }

    func syncNotifications() {
        notifier.sync(appState.portal.sessions, preferences)
    }

    func exportICS() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PUPSIS-Schedule.ics"
        if let ics = UTType(filenameExtension: "ics") {
            panel.allowedContentTypes = [ics]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = ICSExporter.ics(
            for: appState.portal.sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            // Term status: an .ics VEVENT is a single repeating series, so it
            // carries whole-term status, not a single week's exception.
            status: { preferences.termStatus(for: $0) }
        )
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportResult = "Saved schedule to “\(url.lastPathComponent)”."
        } catch {
            exportResult = error.localizedDescription
        }
    }

    func exportClasses() {
        exportResult = calendar.exportClasses(
            appState.portal.sessions,
            weekStart: Weekday.weekStart(containing: .now),
            until: preferences.termEndDate,
            toCalendarID: preferences.exportCalendarID,
            onlineCalendarID: preferences.onlineExportCalendarID.isEmpty ? nil : preferences.onlineExportCalendarID,
            status: { preferences.status(for: $0, on: $1) }
        )
    }
}

private struct SubjectColorRow: View {
    let code: String
    @ObservedObject var preferences: Preferences
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            // Binding rather than onChange: ColorPicker writes continuously
            // while the user drags, and the swatch has to follow.
            ColorPicker(
                selection: Binding(
                    get: { preferences.color(for: code, in: palette) },
                    set: { preferences.setColor($0, for: code) }
                ),
                supportsOpacity: false
            ) {
                Text(code)
                    .font(Theme.Typo.blockCode)
            }

            Spacer()

            Button("Reset") { preferences.resetColor(for: code) }
                .buttonStyle(.link)
                .disabled(!preferences.hasCustomColor(for: code))
        }
    }
}
