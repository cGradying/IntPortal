import SwiftUI
import AppKit

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

    /// The note key of the selected row/file, or nil to fall back to the day note.
    @State private var selectedKey: String?

    /// Notes opened as tabs above the editor, in open order.
    @State private var openTabs: [String] = []

    /// Which day the "Day note" navigator points at (browse past/future).
    @State private var browsedDay = Date()
    /// Expanded vault folders.
    @State private var expandedFolders: Set<UUID> = []
    /// A pending name entry (new file/folder or rename).
    @State private var naming: NamingRequest?
    @State private var namingText = ""
    /// A vault node awaiting delete confirmation.
    @State private var pendingDelete: VaultNode?
    @State private var showingDatePicker = false
    /// The folder currently highlighted as a drag-drop target.
    @State private var dropTarget: UUID?

    struct NamingRequest: Identifiable {
        let id = UUID()
        let title: String
        let commit: (String) -> Void
    }

    private var now: Date { appState.now }
    private var nowMinutes: Int { NowLine.minutes(of: now) }

    /// True when the navigator is on the actual current day — only then are the
    /// live phases (in session / countdown / free time) meaningful.
    private var isBrowsingToday: Bool { Calendar.current.isDate(browsedDay, inSameDayAs: now) }
    /// The clock the agenda is built against: the real now for today, else the
    /// start of the browsed day so its classes all read as the day's schedule.
    private var referenceNow: Date { isBrowsingToday ? now : Calendar.current.startOfDay(for: browsedDay) }
    private var weekStart: Date { Weekday.weekStart(containing: referenceNow) }

    /// The browsed day's classes as vacancy-aware phased items — source of the
    /// tomorrow line and the empty state.
    private var agenda: DayAgenda {
        DayAgenda.make(
            sessions: appState.portal.sessions,
            now: referenceNow,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            }
        )
    }

    /// Classes merged with the browsed day's custom calendar events, sorted and phased.
    private var entries: [DayAgenda.AgendaEntry] {
        DayAgenda.timeline(
            classes: appState.portal.sessions,
            events: calendar.todayBlocks(calendarIDs: preferences.visibleCalendarIDs, on: referenceNow),
            now: referenceNow,
            isVacant: { session, date in
                preferences.status(for: session, on: Weekday.weekStart(containing: date)) == .vacant
            }
        )
    }

    /// The note the editor is showing — a tapped row/file's, or the browsed day's
    /// scratchpad when nothing is explicitly selected.
    private var currentKey: String { selectedKey ?? dayKey(for: browsedDay) }

    var body: some View {
        HStack(spacing: 0) {
            noteEditorPane
            Divider()
            sidebar
                .frame(width: 300)
        }
        .navigationTitle("Today")
        .onAppear { appeared = true }
        .alert(naming?.title ?? "", isPresented: namingPresented, presenting: naming) { request in
            TextField("Name", text: $namingText)
            Button("OK") { request.commit(namingText); naming = nil }
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: deletePresented,
            presenting: pendingDelete
        ) { node in
            Button("Delete", role: .destructive) { confirmDelete(node) }
        } message: { node in
            Text(node.isFolder ? "This deletes the folder and everything inside it." : "This note will be deleted.")
        }
    }

    private var namingPresented: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }
    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: Editor pane (main)

    private var noteEditorPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            tabBar
            Text(noteTitle(for: currentKey))
                .font(Theme.Typo.detailTitle)
                .lineLimit(1)

            WebNoteEditor(
                notes: notes,
                noteKey: currentKey,
                title: noteTitle(for: currentKey),
                onOpenNote: openNote(titled:)
            )
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvasWash)
        // Every explicit note open (tap a file/row/day, wikilink, drop) becomes a tab.
        .onChange(of: selectedKey) { _, new in
            if let new, !openTabs.contains(new) { openTabs.append(new) }
        }
    }

    /// Open notes as closeable tabs. A vault file dragged onto the bar opens too.
    @ViewBuilder private var tabBar: some View {
        if !openTabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(openTabs, id: \.self) { (key: String) in
                        tabChip(key)
                    }
                }
                .padding(.bottom, 2)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap({ UUID(uuidString: $0) }),
                      let key = notes.noteKey(forNodeID: id) else { return false }
                selectedKey = key
                return true
            }
        }
    }

    private func tabChip(_ key: String) -> some View {
        let active = key == currentKey
        return HStack(spacing: 6) {
            Text(noteTitle(for: key)).font(Theme.Typo.footer).lineLimit(1)
            Button { closeTab(key) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(active ? palette.accent.opacity(0.16) : Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(palette.accent.opacity(active ? 0.4 : 0), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key }
    }

    private func closeTab(_ key: String) {
        openTabs.removeAll { $0 == key }
        // If the closed tab was showing, fall back to the last remaining tab
        // (or nil → today's day note).
        if selectedKey == key { selectedKey = openTabs.last }
    }

    /// Resolve a clicked `[[wikilink]]` title to an existing note and open it.
    /// (Full vault navigation arrives with the vault round.)
    private func openNote(titled title: String) {
        if let entry = entries.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            selectedKey = noteKey(entry)
        } else if let match = notes.notes.first(where: { $0.value.title?.caseInsensitiveCompare(title) == .orderedSame }) {
            selectedKey = match.key
        }
    }

    // MARK: Sidebar — schedule + note history

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    dailyNoteRow

                    if entries.isEmpty {
                        Text("Nothing scheduled today.")
                            .font(Theme.Typo.footer)
                            .foregroundStyle(.secondary)
                    } else {
                        timeline
                    }

                    tomorrowLine
                }

                Divider()
                vaultSection

                if !history.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All notes")
                            .font(Theme.Typo.detailMeta)
                            .foregroundStyle(.secondary)
                        ForEach(history, id: \.key) { item in
                            sidebarItem(
                                title: item.title,
                                subtitle: Self.shortDate.string(from: item.updated),
                                key: item.key,
                                hasNote: true
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(palette.canvasWash)
    }

    // MARK: Daily-note navigator (browse any date)

    private var dailyNoteRow: some View {
        HStack(spacing: 4) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Previous day")

            let key = dayKey(for: browsedDay)
            Button { selectedKey = key } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Day note").font(Theme.Typo.footer)
                        Text(Self.shortDate.string(from: browsedDay))
                            .font(Theme.Typo.detailMeta).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if notes.hasNote(for: key) { noteDot }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(key == currentKey ? palette.accent.opacity(0.14) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.accent.opacity(key == currentKey ? 0.4 : 0), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { noteActions(for: key) }

            Button { showingDatePicker = true } label: { Image(systemName: "calendar") }
                .buttonStyle(.borderless)
                .help("Pick a date")
                .popover(isPresented: $showingDatePicker) {
                    DatePicker("", selection: $browsedDay, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }

            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help("Next day")
        }
    }

    private func shiftDay(_ delta: Int) {
        browsedDay = Calendar.current.date(byAdding: .day, value: delta, to: browsedDay) ?? browsedDay
    }

    // MARK: Vault (folders + files)

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Vault").font(Theme.Typo.detailMeta).foregroundStyle(.secondary)
                Spacer()
                Button { promptNewFile(parent: nil) } label: { Image(systemName: "doc.badge.plus") }
                    .help("New note")
                Button { promptNewFolder(parent: nil) } label: { Image(systemName: "folder.badge.plus") }
                    .help("New folder")
            }
            .buttonStyle(.borderless)

            if notes.vault.isEmpty {
                Text("No files yet — add a note or folder.")
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                ForEach(notes.vault) { node in
                    vaultRow(node, depth: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Drop onto the section background (not a folder) moves an item to the root.
        .dropDestination(for: String.self) { items, _ in handleDrop(items, into: nil) }
    }

    // AnyView: the function is recursive, so the opaque `some View` can't be
    // inferred in terms of itself.
    private func vaultRow(_ node: VaultNode, depth: Int) -> AnyView {
        if node.isFolder {
            return AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    folderRow(node, depth: depth)
                    if expandedFolders.contains(node.id) {
                        ForEach(node.children ?? []) { child in
                            vaultRow(child, depth: depth + 1)
                        }
                    }
                }
            )
        }
        return AnyView(fileRow(node, depth: depth))
    }

    private func folderRow(_ node: VaultNode, depth: Int) -> some View {
        let open = expandedFolders.contains(node.id)
        return HStack(spacing: 6) {
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(node.name).font(Theme.Typo.footer).lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 6).fill(dropTarget == node.id ? palette.accent.opacity(0.12) : .clear))
        .onTapGesture { toggleFolder(node.id) }
        .draggable(node.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, into: node.id)
        } isTargeted: { targeted in
            dropTarget = targeted ? node.id : (dropTarget == node.id ? nil : dropTarget)
        }
        .contextMenu {
            Button("New note") { promptNewFile(parent: node.id) }
            Button("New folder") { promptNewFolder(parent: node.id) }
            Button("Rename") { promptRename(node) }
            Button("Delete", role: .destructive) { pendingDelete = node }
        }
    }

    private func fileRow(_ node: VaultNode, depth: Int) -> some View {
        let selected = node.noteKey == currentKey
        return HStack(spacing: 6) {
            Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 10)
            Text(node.name).font(Theme.Typo.footer).lineLimit(1)
            Spacer(minLength: 4)
            if let key = node.noteKey, notes.hasNote(for: key) { noteDot }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, CGFloat(depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? palette.accent.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if let key = node.noteKey { selectedKey = key } }
        .draggable(node.id.uuidString)
        .contextMenu {
            if let key = node.noteKey {
                Button("Copy text") { copyNoteText(key) }
                Button("Share as…") { exportNote(key) }
                Divider()
            }
            Button("Rename") { promptRename(node) }
            Button("Delete", role: .destructive) { pendingDelete = node }
        }
    }

    /// Move a dragged node (by id string) into `parent` (root when nil).
    private func handleDrop(_ items: [String], into parent: UUID?) -> Bool {
        dropTarget = nil
        guard let id = items.first.flatMap({ UUID(uuidString: $0) }) else { return false }
        notes.move(id, to: parent)
        if let parent { expandedFolders.insert(parent) }
        return true
    }

    private func toggleFolder(_ id: UUID) {
        if expandedFolders.contains(id) { expandedFolders.remove(id) } else { expandedFolders.insert(id) }
    }

    private func promptNewFile(parent: UUID?) {
        namingText = ""
        naming = NamingRequest(title: "New note") { name in
            let key = notes.addFile(name: name, to: parent)
            if let parent { expandedFolders.insert(parent) }
            selectedKey = key
        }
    }

    private func promptNewFolder(parent: UUID?) {
        namingText = ""
        naming = NamingRequest(title: "New folder") { name in
            let id = notes.addFolder(name: name, to: parent)
            expandedFolders.insert(id)
            if let parent { expandedFolders.insert(parent) }
        }
    }

    private func promptRename(_ node: VaultNode) {
        namingText = node.name
        naming = NamingRequest(title: "Rename") { name in notes.renameItem(node.id, to: name) }
    }

    private func confirmDelete(_ node: VaultNode) {
        notes.deleteItem(node.id)
        // Drop tabs for any vault file that no longer exists, and if the open note
        // was inside what we deleted, fall back to the day note.
        openTabs.removeAll { $0.hasPrefix("vault:") && notes.vaultName(forKey: $0) == nil }
        if let key = selectedKey, key.hasPrefix("vault:"), notes.vaultName(forKey: key) == nil {
            selectedKey = nil
        }
        pendingDelete = nil
    }

    // MARK: Note actions (copy / export / delete)

    private func copyNoteText(_ key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes.text(for: key), forType: .string)
    }

    /// "Share as" — write the note's Markdown to a file the user picks.
    private func exportNote(_ key: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = noteTitle(for: key).replacingOccurrences(of: "/", with: "-") + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? notes.text(for: key).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Clear a day/class/event note (they aren't vault files, so emptying is the
    /// delete — history hides empty notes). Falls the editor back to the day note.
    private func clearNote(_ key: String) {
        notes.setText("", for: key, title: nil)
        if selectedKey == key { selectedKey = nil }
    }

    /// The copy / export / delete actions shared by day, class, event and history notes.
    @ViewBuilder private func noteActions(for key: String) -> some View {
        Button("Copy text") { copyNoteText(key) }
        Button("Share as…") { exportNote(key) }
        if notes.hasNote(for: key) {
            Button("Delete", role: .destructive) { clearNote(key) }
        }
    }

    /// A compact, selectable sidebar row (Day note + history). The rich agenda
    /// rows keep their own look via `row(for:)`.
    private func sidebarItem(title: String, subtitle: String? = nil, key: String, hasNote: Bool) -> some View {
        let selected = key == currentKey
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Typo.footer).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(Theme.Typo.detailMeta).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if hasNote { noteDot }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? palette.accent.opacity(0.14) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.accent.opacity(selected ? 0.4 : 0), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key }
        .contextMenu { noteActions(for: key) }
    }

    /// Every note with content, newest first — the history the sidebar lists.
    private var history: [(key: String, title: String, updated: Date)] {
        notes.notes
            // Vault files live in the tree above, so keep them out of the flat list.
            .filter { !$0.key.hasPrefix("vault:") && !$0.value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (key: $0.key, title: noteTitle(for: $0.key), updated: $0.value.updated) }
            .sorted { $0.updated > $1.updated }
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(referenceNow.formatted(.dateTime.weekday(.wide)))
                    .font(Theme.Typo.detailTitle)
                if !isBrowsingToday {
                    Button("Today") { browsedDay = now }
                        .font(Theme.Typo.footer)
                        .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 6) {
                Text(referenceNow.formatted(.dateTime.month(.wide).day()))
                // Live free-time only reads correctly for the actual current day.
                if isBrowsingToday {
                    let free = DayAgenda.remainingFreeMinutes(entries, nowMinutes: nowMinutes)
                    if free > 0 {
                        Text("·")
                        Text("\(duration(free)) free")
                    }
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
        let selected = key == currentKey

        Group {
            if let session = entry.session {
                classRow(entry, session: session, hasNote: notes.hasNote(for: key))
            } else {
                eventRow(entry, hasNote: notes.hasNote(for: key))
            }
        }
        // Tapping a row loads its note into the editor pane.
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
            Text(isBrowsingToday ? upcoming(for: session).countdown(now: now) : "at \(ClassSession.format(session.start))")
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

    /// The freeform day scratchpad's key for a given calendar day. Uses the
    /// local-timezone formatter so the key matches the day the user sees — a
    /// GMT-based ISO format shifts midnight-local dates to the previous day.
    private func dayKey(for date: Date) -> String {
        "day:\(Self.isoDay.string(from: date))"
    }

    /// Today's day-note key — the editor's default when nothing else is selected.
    private var dayKey: String { dayKey(for: now) }

    /// A human title for any note key — today's entry title when the class/event
    /// is on today's schedule, else derived from the key (or a stored title, for
    /// history notes whose class/event isn't scheduled today).
    private func noteTitle(for key: String) -> String {
        if key.hasPrefix("vault:") { return notes.vaultName(forKey: key) ?? "Untitled" }
        if let entry = entries.first(where: { noteKey($0) == key }) { return entry.title }
        if key.hasPrefix("class:") { return String(key.dropFirst("class:".count)) }
        if key.hasPrefix("day:") {
            let iso = String(key.dropFirst("day:".count))
            if let date = Self.isoDay.date(from: iso) { return Self.shortDate.string(from: date) }
            return iso
        }
        return notes.note(for: key)?.title ?? "Note"
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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
