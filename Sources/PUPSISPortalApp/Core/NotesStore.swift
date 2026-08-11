import Foundation

/// A single note — free text, when it last changed, and an optional display
/// title so the notes history can label a note whose class/event isn't on today's
/// schedule. `title` is optional so older `notes.json` files still decode.
struct Note: Codable, Equatable {
    var text: String
    var updated: Date
    var title: String?
}

/// A node in the user's freeform notes vault: either a folder (with `children`)
/// or a file (with a `noteKey` into the notes dict). The tree is user-built —
/// create folders, create named notes, nest them — separate from the
/// schedule-linked notes (class/day/event) which stay keyed automatically.
struct VaultNode: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var isFolder: Bool
    /// Folder contents. nil/`[]` for files.
    var children: [VaultNode]?
    /// The notes-dict key holding this file's text. nil for folders.
    var noteKey: String?

    init(id: UUID = UUID(), name: String, isFolder: Bool, children: [VaultNode]? = nil, noteKey: String? = nil) {
        self.id = id
        self.name = name
        self.isFolder = isFolder
        self.children = children
        self.noteKey = noteKey
    }
}

/// Notes the user attaches from the Today screen: one per class or event, plus a
/// freeform per-day scratchpad, plus a user-built vault of folders and files.
/// Keyed by an opaque string the caller chooses (subject code for a class, event
/// id for an event, the date for a day note, `vault:<uuid>` for a vault file).
///
/// A document, like `ScheduleStore` — JSON in Application Support, file `0600` —
/// but held as an injectable `@MainActor ObservableObject` (like `Preferences`)
/// so the panel binds to it live and tests can point it at a temp file.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [String: Note]
    @Published private(set) var vault: [VaultNode]
    private let url: URL

    /// On-disk shape. A bare `[String: Note]` (the legacy format) still loads —
    /// see `load(from:)`.
    private struct Document: Codable {
        var notes: [String: Note]
        var vault: [VaultNode]
    }

    static let defaultURL: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("notes.json")
    }()

    init(url: URL = defaultURL) {
        self.url = url
        let document = Self.load(from: url)
        notes = document.notes
        vault = document.vault
    }

    func note(for key: String) -> Note? { notes[key] }

    func text(for key: String) -> String { notes[key]?.text ?? "" }

    /// True only when there's actual content — an all-whitespace note reads as
    /// none, so the dot on a Today row means "there's something written here".
    func hasNote(for key: String) -> Bool {
        !(notes[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Sets a note's text, persisting immediately. Empty (or whitespace-only)
    /// text deletes the note rather than keeping a blank one around. A non-nil
    /// `title` is recorded so history can label the note later; passing nil keeps
    /// whatever title was already stored.
    func setText(_ text: String, for key: String, title: String? = nil) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard notes[key] != nil else { return }
            notes[key] = nil
        } else {
            notes[key] = Note(text: text, updated: Date(), title: title ?? notes[key]?.title)
        }
        persist()
    }

    // MARK: Vault CRUD

    /// Create a folder under `parentID` (root when nil). Returns its id.
    @discardableResult
    func addFolder(name: String, to parentID: UUID?) -> UUID {
        let node = VaultNode(name: cleaned(name, fallback: "New folder"), isFolder: true, children: [])
        insert(node, into: parentID, in: &vault)
        persist()
        return node.id
    }

    /// Create a file under `parentID` (root when nil). Returns its note key, so the
    /// caller can open it in the editor. The note itself is created on first save.
    @discardableResult
    func addFile(name: String, to parentID: UUID?) -> String {
        let key = "vault:\(UUID().uuidString)"
        let node = VaultNode(name: cleaned(name, fallback: "Untitled"), isFolder: false, noteKey: key)
        insert(node, into: parentID, in: &vault)
        persist()
        return key
    }

    func renameItem(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = mutate(id, in: &vault) { $0.name = trimmed }
        // Keep the file's stored note title in step, so history matches the tree.
        if let key = node(id, in: vault)?.noteKey, notes[key] != nil {
            notes[key]?.title = trimmed
        }
        persist()
    }

    /// Move a node into `newParentID` (root when nil). No-ops if the target is the
    /// node itself or one of its descendants (which would detach the subtree).
    func move(_ id: UUID, to newParentID: UUID?) {
        if id == newParentID { return }
        if let target = newParentID, isDescendant(target, ofAncestor: id) { return }
        var picked: VaultNode?
        detach(id, from: &vault, picked: &picked)
        guard let node = picked else { return }
        insert(node, into: newParentID, in: &vault)
        persist()
    }

    /// Remove a node (and, for a folder, its whole subtree) plus any notes it held.
    func deleteItem(_ id: UUID) {
        var removedKeys: [String] = []
        remove(id, from: &vault, removedKeys: &removedKeys)
        for key in removedKeys { notes[key] = nil }
        persist()
    }

    /// The display name of the vault file holding `key`, if any.
    func vaultName(forKey key: String) -> String? {
        node(withKey: key, in: vault)?.name
    }

    /// The note key a vault node (by id) points at — for opening a dragged file.
    func noteKey(forNodeID id: UUID) -> String? {
        node(id, in: vault)?.noteKey
    }

    // MARK: Tree helpers (recursive over the value-type tree)

    private func cleaned(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func insert(_ node: VaultNode, into parentID: UUID?, in nodes: inout [VaultNode]) {
        guard let parentID else { nodes.append(node); return }
        for i in nodes.indices {
            if nodes[i].id == parentID {
                if nodes[i].children == nil { nodes[i].children = [] }
                nodes[i].children!.append(node)
                return
            }
            if nodes[i].children != nil {
                insert(node, into: parentID, in: &nodes[i].children!)
            }
        }
    }

    @discardableResult
    private func mutate(_ id: UUID, in nodes: inout [VaultNode], _ change: (inout VaultNode) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id { change(&nodes[i]); return true }
            if nodes[i].children != nil, mutate(id, in: &nodes[i].children!, change) { return true }
        }
        return false
    }

    private func remove(_ id: UUID, from nodes: inout [VaultNode], removedKeys: inout [String]) {
        for i in nodes.indices {
            if nodes[i].id == id {
                collectKeys(nodes[i], into: &removedKeys)
                nodes.remove(at: i)
                return
            }
            if nodes[i].children != nil {
                remove(id, from: &nodes[i].children!, removedKeys: &removedKeys)
            }
        }
    }

    /// Detach a node from the tree, handing it back via `picked` (keeps its
    /// subtree intact for re-insertion elsewhere).
    private func detach(_ id: UUID, from nodes: inout [VaultNode], picked: inout VaultNode?) {
        for i in nodes.indices {
            if nodes[i].id == id {
                picked = nodes[i]
                nodes.remove(at: i)
                return
            }
            if nodes[i].children != nil {
                detach(id, from: &nodes[i].children!, picked: &picked)
                if picked != nil { return }
            }
        }
    }

    /// Is `candidate` inside `ancestor`'s subtree?
    private func isDescendant(_ candidate: UUID, ofAncestor ancestor: UUID) -> Bool {
        guard let root = node(ancestor, in: vault) else { return false }
        return node(candidate, in: root.children ?? []) != nil
    }

    private func collectKeys(_ node: VaultNode, into keys: inout [String]) {
        if let key = node.noteKey { keys.append(key) }
        for child in node.children ?? [] { collectKeys(child, into: &keys) }
    }

    private func node(_ id: UUID, in nodes: [VaultNode]) -> VaultNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = node.children.flatMap({ self.node(id, in: $0) }) { return found }
        }
        return nil
    }

    private func node(withKey key: String, in nodes: [VaultNode]) -> VaultNode? {
        for node in nodes {
            if node.noteKey == key { return node }
            if let found = node.children.flatMap({ self.node(withKey: key, in: $0) }) { return found }
        }
        return nil
    }

    // MARK: Disk

    private func persist() {
        guard let data = try? JSONEncoder().encode(Document(notes: notes, vault: vault)) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // The user's own notes — readable by them, nobody else on the machine.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func load(from url: URL) -> Document {
        guard let data = try? Data(contentsOf: url) else { return Document(notes: [:], vault: []) }
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(Document.self, from: data) { return document }
        // Legacy format: a bare notes dict, no vault yet.
        if let legacy = try? decoder.decode([String: Note].self, from: data) {
            return Document(notes: legacy, vault: [])
        }
        return Document(notes: [:], vault: [])
    }
}
