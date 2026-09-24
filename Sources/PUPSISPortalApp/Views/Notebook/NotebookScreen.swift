import SwiftUI
import AppKit
import Inject

/// The Notebook (⌘4): a vault sheet (`NotebookVault`) — the "Today's note"
/// day navigator, nested folders and files, "All notes" history — beside an
/// editor sheet for whichever note is open.
///
/// The class/event timeline this screen used to show (the old `AgendaView`)
/// is Today's own screen now (`Views/Today/TodayScreen.swift`, a sibling
/// slice); this view keeps only the day-note *navigator*, not the schedule
/// it used to browse alongside.
///
/// The vault is its own `View` (below) rather than inlined here, on purpose:
/// it needs only `NotesStore` and a `selectedKey` binding, never `AppState` —
/// which matters because `AppState.init()` reads the real Keychain whenever
/// the process isn't launched with `-IntPortalDemo` (`PUPSISPortalApp.swift`,
/// `credentials = KeychainStore.load()`), so a plain `AppState()` inside
/// `swift test` blocks for minutes (confirmed live, twice — see this
/// screen's snapshot tests). `NotebookVault` sidesteps that landmine
/// entirely and is what those tests actually render.
struct NotebookScreen: View {
    @ObserveInjection var inject
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: Preferences
    /// Unused now that the today timeline (its own reader of `calendar`)
    /// moved out — kept as a plain `let`, not `@ObservedObject`, so this
    /// view no longer resubscribes to it. Stays a parameter because
    /// `AppShell`'s `.today, .notebook` case (owned by a sibling slice)
    /// still passes it positionally.
    let calendar: CalendarBridge
    @ObservedObject var notes: NotesStore
    /// False renders the vault flat, without its `ScrollView` — `ImageRenderer`
    /// (`Snapshot.render`) can't draw a `ScrollView`'s content, so the snapshot
    /// suite renders the vault this way. Always `true` in the running app.
    var scrolls = true
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    /// The note key open in the editor, or nil for the empty state — no
    /// longer defaults silently to today's day note (see `NotebookEmptyEditorState`).
    /// Shared with `NotebookVault` via a binding: tapping a row there opens
    /// it here.
    @State private var selectedKey: String?

    /// Notes opened as tabs above the editor, in open order.
    @State private var openTabs: [String] = []

    /// Sidebar width captured at the start of a resize drag, so the handle
    /// accumulates from a fixed point rather than re-reading the (already
    /// mutating) preference mid-drag — same convention as
    /// `AssistantFloating`'s `resizeGrip`.
    @State private var sidebarWidthAtDragStart: Double?
    @State private var sidebarHandleHovered = false

    private var now: Date { appState.now }

    /// The note the editor shows — nil reads as the empty state.
    private var currentKey: String? { selectedKey }

    var body: some View {
        HStack(spacing: 0) {
            if preferences.notebookSidebarOnLeft {
                vault.frame(width: preferences.notebookSidebarWidth)
                sidebarResizeHandle
                editorSheet
            } else {
                editorSheet
                sidebarResizeHandle
                vault.frame(width: preferences.notebookSidebarWidth)
            }
        }
        .navigationTitle("Notebook")
        .enableInjection()
    }

    private var vault: some View {
        NotebookVault(notes: notes, selectedKey: $selectedKey, scrolls: scrolls)
    }

    // MARK: Editor sheet (main)

    private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 6) {
            tabBar
            if let key = currentKey {
                editorHeader(for: key)
                WebNoteEditor(
                    notes: notes,
                    preferences: preferences,
                    noteKey: key,
                    title: Self.noteTitle(notes: notes, for: key),
                    bridge: appState.noteBridge,
                    onOpenNote: openNote(titled:)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                NotebookEmptyEditorState(onNewNote: { selectedKey = notes.addFile(name: "Untitled", to: nil) })
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.roles.sheet, in: PixelNotch())
        .overlay(PixelNotch().strokeBorder(palette.roles.line, lineWidth: 1))
        // Every explicit note open (tap a file/row/day, wikilink, drop) becomes a tab.
        .onChange(of: selectedKey) { _, new in
            if let new, !openTabs.contains(new) { openTabs.append(new) }
        }
        // The assistant panel floats outside this view and needs to know
        // "the note you're looking at" — selectedKey/openTabs stay private
        // (they're this screen's own tab-bar bookkeeping), but the resolved
        // key is mirrored up so a request like "summarize this note" works
        // from anywhere, not just from inside NotebookScreen. `noteAddDateOptions`
        // rides along the same mirror — the floating deck's date menu
        // (`Views/AssistantFloating.swift`) needs it and lives outside this
        // view too.
        .onChange(of: currentKey) { _, new in
            appState.openNoteKey = new
            appState.noteAddDateOptions = new.flatMap(addDateOptions(for:))
        }
        .onAppear {
            appState.openNoteKey = currentKey
            appState.noteAddDateOptions = currentKey.flatMap(addDateOptions(for:))
        }
    }

    /// Kicker (note kind, subject-coloured) + title (display face, 27pt) +
    /// meta line, above the web editor — `NotebookEditorHeader` below, which
    /// doesn't touch `WebNoteEditor`'s `WKWebView` so it can be snapshotted
    /// on its own (`ImageRenderer` can't draw a `WKWebView`).
    private func editorHeader(for key: String) -> some View {
        NotebookEditorHeader(kicker: kicker(for: key), title: titleBinding(for: key), meta: metaLine(for: key))
    }

    /// "COMP 001 · class note" style label, in the subject's colour for a
    /// class note. Vault files have no fixed kind, so no kicker.
    private func kicker(for key: String) -> (label: String, color: Color)? {
        if key.hasPrefix("class:") {
            let code = String(key.dropFirst("class:".count))
            return ("\(code) · class note", preferences.color(for: code, in: palette))
        }
        if key.hasPrefix("event:") { return ("Event note", palette.roles.ink2) }
        if key.hasPrefix("day:") {
            let iso = String(key.dropFirst("day:".count))
            let isToday = Self.isoDay.string(from: now) == iso
            return (isToday ? "Today's note" : "Day note", palette.roles.ink2)
        }
        return nil
    }

    private func metaLine(for key: String) -> String {
        guard let updated = notes.note(for: key)?.updated else { return "New note · select any text to Ask AI" }
        return "Edited \(Self.shortDate.string(from: updated)) · select any text to Ask AI"
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
                .animation(Motion.arrival(reduced: reduceMotion), value: openTabs)
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
            Text(Self.noteTitle(notes: notes, for: key)).font(typography.footer).lineLimit(1)
            Button { closeTab(key) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(active ? palette.roles.actionSoft : palette.roles.sunk, in: PixelNotch())
        .foregroundStyle(active ? palette.roles.actionInk : palette.roles.ink)
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key }
    }

    private func closeTab(_ key: String) {
        openTabs.removeAll { $0 == key }
        // If the closed tab was showing, fall back to the last remaining tab
        // (or nil → the empty state).
        if selectedKey == key { selectedKey = openTabs.last }
    }

    /// Resolve a clicked `[[wikilink]]` title to an existing note and open it.
    private func openNote(titled title: String) {
        if let key = notes.key(forName: title) {
            selectedKey = key
        } else if let match = notes.notes.first(where: { $0.value.title?.caseInsensitiveCompare(title) == .orderedSame }) {
            selectedKey = match.key
        }
    }

    /// A draggable divider between the note editor and the vault sheet — a
    /// `Divider()` with a wider invisible hit area so the drag doesn't need
    /// pixel-perfect aim, and a resize cursor on hover. Double-click resets
    /// to the default width, matching `AssistantFloating`'s resize grip.
    private var sidebarResizeHandle: some View {
        Divider()
            .overlay(alignment: .center) {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
            }
            .background(sidebarHandleHovered ? palette.roles.action.opacity(0.3) : .clear)
            .onHover { inside in
                sidebarHandleHovered = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = sidebarWidthAtDragStart ?? preferences.notebookSidebarWidth
                        if sidebarWidthAtDragStart == nil { sidebarWidthAtDragStart = start }
                        // Sign flips with which side the sidebar is on: on
                        // the right, dragging left (negative dx) widens it;
                        // on the left, dragging right (positive dx) does.
                        let dx = preferences.notebookSidebarOnLeft ? value.translation.width : -value.translation.width
                        preferences.setNotebookSidebarWidth(start + dx)
                    }
                    .onEnded { _ in sidebarWidthAtDragStart = nil }
            )
            .onTapGesture(count: 2) { preferences.resetNotebookSidebarWidth() }
            .help("Drag to resize · double-click to reset")
    }

    // MARK: Notes

    /// "Next class" / "Today" date labels for the Add-date menu, shown only
    /// when the open note is a shared per-subject class note. `next` is the
    /// next date (today or later) the subject meets, by weekday; `today` is
    /// always just today. When they land on the same day the toolbar collapses
    /// them into one option.
    private func addDateOptions(for key: String) -> (next: String, today: String)? {
        guard key.hasPrefix("class:") else { return nil }
        let subjectCode = String(key.dropFirst("class:".count))
        let todayLabel = Self.shortDate.string(from: now)
        guard let next = ClassSession.nextMeetingDate(for: subjectCode, in: appState.portal.sessions, from: now) else {
            return nil
        }
        return (next: Self.shortDate.string(from: next), today: todayLabel)
    }

    /// The title field's binding for `key`: reads the resolved title, writes
    /// back through `renameVaultFile` for vault-backed notes (keeps the vault
    /// name in step) or `setTitle` for everything else.
    private func titleBinding(for key: String) -> Binding<String> {
        Binding(
            get: { Self.noteTitle(notes: notes, for: key) },
            set: { newValue in
                if key.hasPrefix("vault:") {
                    notes.renameVaultFile(forKey: key, to: newValue)
                } else {
                    notes.setTitle(newValue, for: key)
                }
            }
        )
    }

    fileprivate static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    fileprivate static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A human title for any note key — never the raw text or an AI prompt.
    /// A user-set title (typed into the title field, `notes.setTitle`/
    /// `renameVaultFile`) always wins; otherwise it's the note's own first
    /// Markdown heading (`vaultDisplayTitle`); otherwise a key-derived
    /// fallback (the subject code, the date, or "Note"). `fileprivate` (not
    /// an instance method) so both this screen (tabs, the title field) and
    /// `NotebookVault` (folder/file names, history) share one implementation
    /// without either needing the other's stored state.
    fileprivate static func noteTitle(notes: NotesStore, for key: String) -> String {
        if key.hasPrefix("vault:") { return notes.vaultName(forKey: key) ?? "Untitled" }
        let fallback: String
        if key.hasPrefix("class:") {
            fallback = String(key.dropFirst("class:".count))
        } else if key.hasPrefix("day:") {
            let iso = String(key.dropFirst("day:".count))
            fallback = isoDay.date(from: iso).map(shortDate.string(from:)) ?? iso
        } else {
            fallback = "Note"
        }
        return vaultDisplayTitle(text: notes.text(for: key), override: notes.note(for: key)?.title, fallback: fallback)
    }

    /// A note's display title, in priority order: a user-set override, then
    /// the note's own first Markdown heading, then `fallback`. Pure and
    /// key-independent so it's directly testable — the vault (and history,
    /// tabs, export filenames) must never show a raw AI prompt or the note's
    /// opaque storage key as its title.
    static func vaultDisplayTitle(text: String, override: String?, fallback: String) -> String {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return override }
        if let heading = firstHeading(in: text) { return heading }
        return fallback
    }

    /// The text of the first Markdown heading line (`#`…`######`) anywhere in
    /// `text`, or nil if there isn't one.
    private static func firstHeading(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let stripped = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }
}

/// The editor sheet's own header: kicker (note kind, subject-coloured) +
/// title (display face, 27pt) + meta line. Split out of `NotebookScreen` so
/// it's a plain, `AppState`/`WKWebView`-free view — snapshottable on its own.
struct NotebookEditorHeader: View {
    let kicker: (label: String, color: Color)?
    @Binding var title: String
    let meta: String
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let kicker {
                Text(kicker.label)
                    .font(typography.display(size: 13))
                    .foregroundStyle(kicker.color)
            }
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(typography.display(size: 27, weight: .bold))
                .lineLimit(1)
            Text(meta)
                .font(typography.detailMeta)
                .foregroundStyle(palette.roles.ink3)
        }
    }
}

/// Shown instead of the web editor when nothing's open — the vault (or the
/// "Today's note" row) picks a note, or this starts one. No `AppState`
/// either, same reasoning as `NotebookEditorHeader`.
struct NotebookEmptyEditorState: View {
    let onNewNote: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text("Pick a note or start one")
                .font(typography.detailBody)
                .foregroundStyle(palette.roles.ink2)
            Button("New note", action: onNewNote)
                .buttonStyle(.pixelPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The vault sheet: the "Today's note" day navigator, nested folders and
/// files (drag to move, full context menu), and "All notes" history. Needs
/// only `NotesStore` and a `selectedKey` binding — no `AppState` — so it
/// (unlike `NotebookScreen` as a whole) is safe and fast to snapshot in
/// `swift test` (see `NotebookScreen`'s own doc comment for why that split
/// exists).
struct NotebookVault: View {
    @ObservedObject var notes: NotesStore
    @Binding var selectedKey: String?
    /// False renders without the `ScrollView` — see `NotebookScreen.scrolls`.
    var scrolls = true
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    /// Which day the "Today's note" navigator points at (browse past/future).
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
    /// Shows the per-row RAG-included/excluded chip — off by default so the
    /// vault reads plain until the user actually wants to check.
    @State private var showRAGBadges = false

    struct NamingRequest: Identifiable {
        let id = UUID()
        let title: String
        let commit: (String) -> Void
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }.scrollIndicators(.hidden)
            } else {
                content
            }
        }
        .background(palette.roles.sheet, in: PixelNotch())
        .overlay(PixelNotch().strokeBorder(palette.roles.line, lineWidth: 1))
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                header
                todaysNoteRow

                if notes.vault.isEmpty {
                    Text("No files yet — add a note or folder.")
                        .font(typography.footer)
                        .foregroundStyle(palette.roles.ink3)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                } else {
                    ForEach(notes.vault) { node in
                        vaultRow(node, depth: 0)
                    }
                }
            }
            .contentShape(Rectangle())
            // Drop onto the section background (not a folder) moves an item to the root.
            .dropDestination(for: String.self) { items, _ in handleDrop(items, into: nil) }

            if !history.isEmpty {
                Divider().overlay(palette.roles.line)
                VStack(alignment: .leading, spacing: 4) {
                    Text("All notes")
                        .font(typography.detailMeta)
                        .foregroundStyle(palette.roles.ink3)
                    ForEach(history, id: \.key) { item in
                        sidebarItem(
                            title: item.title,
                            subtitle: NotebookScreen.shortDate.string(from: item.updated),
                            key: item.key,
                            hasNote: true
                        )
                    }
                }
            }
        }
        .padding(16)
        .animation(Motion.selection(reduced: reduceMotion), value: selectedKey)
        .animation(Motion.arrival(reduced: reduceMotion), value: expandedFolders)
    }

    /// "Vault" label + the "N of M in AI search" toggle (per-row sparkle
    /// marks, dimmed when excluded) + new note/new folder.
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text("Vault")
                .font(typography.display(size: 14))
                .tracking(0.84)
                .foregroundStyle(palette.roles.ink2)
            Spacer(minLength: 0)
            Button { showRAGBadges.toggle() } label: {
                Label("\(notes.ragCounts().included) of \(notes.ragCounts().total) in AI search", systemImage: "sparkles")
                    .font(typography.numeric(size: 12))
                    .foregroundStyle(showRAGBadges ? palette.roles.goldInk : palette.roles.ink2)
            }
            .help("Click to show which notes are included")
            .accessibilityLabel("AI search inclusion — \(notes.ragCounts().included) of \(notes.ragCounts().total) notes included")
            Button { promptNewFile(parent: nil) } label: { Image(systemName: "doc.badge.plus") }
                .help("New note")
                .accessibilityLabel("New note")
            Button { promptNewFolder(parent: nil) } label: { Image(systemName: "folder.badge.plus") }
                .help("New folder")
                .accessibilityLabel("New folder")
        }
        .buttonStyle(.borderless)
    }

    // MARK: "Today's note" navigator (browse any date)

    /// Day-note navigator (prev/next, date picker, content dot) — used to sit
    /// above the today timeline; now it's the vault's top entry, since Today
    /// owns the timeline (spec 04).
    private var todaysNoteRow: some View {
        let key = dayKey(for: browsedDay)
        let selected = key == selectedKey
        return HStack(spacing: 4) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Previous day")
                .accessibilityLabel("Previous day")

            Button { selectedKey = key } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Today's note").font(typography.footer)
                        Text(NotebookScreen.shortDate.string(from: browsedDay))
                            .font(typography.detailMeta).foregroundStyle(palette.roles.ink3)
                    }
                    Spacer(minLength: 4)
                    if notes.hasNote(for: key) { noteDot }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? palette.roles.actionSoft : .clear, in: PixelNotch())
                .foregroundStyle(selected ? palette.roles.actionInk : palette.roles.ink)
            }
            .buttonStyle(.plain)
            .contextMenu { noteActions(for: key) }

            Button { showingDatePicker = true } label: { Image(systemName: "calendar") }
                .buttonStyle(.borderless)
                .help("Pick a date")
                .accessibilityLabel("Pick a date")
                .popover(isPresented: $showingDatePicker) {
                    DatePicker("", selection: $browsedDay, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }

            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help("Next day")
                .accessibilityLabel("Next day")
        }
    }

    private func shiftDay(_ delta: Int) {
        browsedDay = Calendar.current.date(byAdding: .day, value: delta, to: browsedDay) ?? browsedDay
    }

    /// The freeform day scratchpad's key for a given calendar day. Uses the
    /// local-timezone formatter so the key matches the day the user sees — a
    /// GMT-based ISO format shifts midnight-local dates to the previous day.
    private func dayKey(for date: Date) -> String {
        "day:\(NotebookScreen.isoDay.string(from: date))"
    }

    // MARK: Vault (folders + files)

    // AnyView: the function is recursive, so the opaque `some View` can't be
    // inferred in terms of itself. `inheritedExcluded` carries an ancestor
    // folder's RAG exclusion down so a child's badge reflects the *effective*
    // state, not just its own flag.
    private func vaultRow(_ node: VaultNode, depth: Int, inheritedExcluded: Bool = false) -> AnyView {
        let effectiveExcluded = inheritedExcluded || node.ragExcluded == true
        if node.isFolder {
            return AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    folderRow(node, depth: depth, effectiveExcluded: effectiveExcluded)
                    if expandedFolders.contains(node.id) {
                        ForEach(node.children ?? []) { child in
                            vaultRow(child, depth: depth + 1, inheritedExcluded: effectiveExcluded)
                        }
                    }
                }
            )
        }
        return AnyView(fileRow(node, depth: depth, effectiveExcluded: effectiveExcluded))
    }

    /// A folder head, in display caps (DESIGN.md's `Pixelify Sans` identity
    /// face, uppercase, tracked) rather than the reading face file rows use.
    private func folderRow(_ node: VaultNode, depth: Int, effectiveExcluded: Bool) -> some View {
        let open = expandedFolders.contains(node.id)
        return HStack(spacing: 6) {
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(.caption2).foregroundStyle(palette.roles.ink3).frame(width: 10)
            Image(systemName: "folder").foregroundStyle(labelColor(node) ?? palette.roles.ink3)
            Text(node.name.uppercased())
                .font(typography.display(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(labelColor(node) ?? palette.roles.ink3)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showRAGBadges { ragBadge(excluded: effectiveExcluded) }
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(dropTarget == node.id ? palette.roles.actionSoft : .clear, in: PixelNotch())
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
            labelMenu(for: node)
            Toggle("Include in AI search", isOn: ragIncludedBinding(for: node))
            Divider()
            Button("Delete", role: .destructive) { pendingDelete = node }
        }
    }

    /// The current note reads as an action-soft row (DESIGN.md's selection
    /// token), everything else plain.
    private func fileRow(_ node: VaultNode, depth: Int, effectiveExcluded: Bool) -> some View {
        let selected = node.noteKey == selectedKey
        return HStack(spacing: 6) {
            Image(systemName: "doc.text").foregroundStyle(labelColor(node) ?? palette.roles.ink3).frame(width: 10)
            Text(node.name).font(typography.footer).foregroundStyle(selected ? palette.roles.actionInk : palette.roles.ink).lineLimit(1)
            Spacer(minLength: 4)
            if showRAGBadges { ragBadge(excluded: effectiveExcluded) }
            if let key = node.noteKey, notes.hasNote(for: key) { noteDot }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, CGFloat(depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.roles.actionSoft : .clear, in: PixelNotch())
        .contentShape(Rectangle())
        .onTapGesture { if let key = node.noteKey { selectedKey = key } }
        .draggable(node.id.uuidString)
        .contextMenu {
            if let key = node.noteKey {
                Button("Copy text") { copyNoteText(key) }
                exportMenu(for: key)
                Divider()
            }
            Button("Rename") { promptRename(node) }
            labelMenu(for: node)
            Toggle("Include in AI search", isOn: ragIncludedBinding(for: node))
            Divider()
            Button("Delete", role: .destructive) { pendingDelete = node }
        }
    }

    /// A node's colour label, resolved from its stored hex — `nil` reads as
    /// "use the row's default secondary tint" everywhere it's used.
    private func labelColor(_ node: VaultNode) -> Color? {
        node.colorHex.flatMap(Color.init(hex:))
    }

    /// The palette's own swatches plus "None" — the fixed-row pattern
    /// `SwatchRow` (`Views/Blocks.swift`) uses for subject colours. A plain SF
    /// Symbol would render monochrome (menus template-tint symbol icons), so
    /// each swatch is baked into a real, non-template `NSImage` dot — the one
    /// way a colour survives into an AppKit menu.
    @ViewBuilder private func labelMenu(for node: VaultNode) -> some View {
        Menu("Label") {
            Button("None") { notes.setColor(nil, for: node.id) }
            ForEach(Array(palette.subjectColors.enumerated()), id: \.offset) { index, swatch in
                Button {
                    notes.setColor(swatch.hex, for: node.id)
                } label: {
                    Label {
                        Text(node.colorHex == swatch.hex ? "Colour \(index + 1) ✓" : "Colour \(index + 1)")
                    } icon: {
                        Self.swatchIcon(swatch)
                    }
                }
            }
        }
    }

    private static func swatchIcon(_ color: Color) -> Image {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(color).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return Image(nsImage: image)
    }

    private func ragIncludedBinding(for node: VaultNode) -> Binding<Bool> {
        Binding(
            get: { node.ragExcluded != true },
            set: { notes.setRAGExcluded(!$0, for: node.id) }
        )
    }

    private func ragBadge(excluded: Bool) -> some View {
        Image(systemName: excluded ? "sparkles.slash" : "sparkles")
            .font(.caption2)
            .foregroundStyle(excluded ? palette.roles.ink3 : palette.roles.goldInk)
            .help(excluded ? "Excluded from AI search" : "Included in AI search")
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
        // If the open note was inside what we deleted, fall back to the
        // empty state. (A stale open *tab* for it, if any, is
        // `NotebookScreen`'s own bookkeeping and prunes itself the next
        // time a tab it can't resolve is closed/reopened.)
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

    /// Export ▸ Markdown / Plain text / PDF, one `NSSavePanel` shared across
    /// the three renderers in `Core/NoteExport.swift`.
    private func exportMenu(for key: String) -> some View {
        Menu("Export") {
            ForEach(NoteExportFormat.allCases) { format in
                Button(format.label) { exportNote(key, as: format) }
            }
        }
    }

    private func exportNote(_ key: String, as format: NoteExportFormat) {
        let title = NotebookScreen.noteTitle(notes: notes, for: key)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let markdown = notes.text(for: key)
        switch format {
        case .markdown:
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        case .plainText:
            try? NoteExport.plainText(from: markdown).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            NoteExport.writePDF(markdown, title: title, to: url)
        }
    }

    /// Clear a day/class/event note (they aren't vault files, so emptying is the
    /// delete — history hides empty notes). Falls the editor back to the empty state.
    private func clearNote(_ key: String) {
        notes.setText("", for: key, title: nil)
        if selectedKey == key { selectedKey = nil }
    }

    /// The copy / export / delete actions shared by day, class, event and history notes.
    @ViewBuilder private func noteActions(for key: String) -> some View {
        Button("Copy text") { copyNoteText(key) }
        exportMenu(for: key)
        if notes.hasNote(for: key) {
            Button("Delete", role: .destructive) { clearNote(key) }
        }
    }

    /// A compact, selectable sidebar row ("All notes" history).
    private func sidebarItem(title: String, subtitle: String? = nil, key: String, hasNote: Bool) -> some View {
        let selected = key == selectedKey
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(typography.footer).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(typography.detailMeta).foregroundStyle(palette.roles.ink3).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if hasNote { noteDot }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.roles.actionSoft : .clear, in: PixelNotch())
        .foregroundStyle(selected ? palette.roles.actionInk : palette.roles.ink)
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key }
        .contextMenu { noteActions(for: key) }
    }

    /// Every note with content, newest first — the history the vault lists.
    private var history: [(key: String, title: String, updated: Date)] {
        notes.notes
            // Vault files live in the tree above, so keep them out of the flat list.
            .filter { !$0.key.hasPrefix("vault:") && !$0.value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (key: $0.key, title: NotebookScreen.noteTitle(notes: notes, for: $0.key), updated: $0.value.updated) }
            .sorted { $0.updated > $1.updated }
    }

    /// The dot on a row that has a note — small enough to read as a mark, not a
    /// control.
    private var noteDot: some View {
        Circle()
            .fill(palette.roles.action)
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}
