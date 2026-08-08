import Foundation

/// A single note — free text plus when it last changed.
struct Note: Codable, Equatable {
    var text: String
    var updated: Date
}

/// Notes the user attaches from the Today screen: one per class or event, plus a
/// freeform per-day scratchpad. Keyed by an opaque string the caller chooses
/// (subject code for a class, event id for an event, the date for the day note).
///
/// A document, like `ScheduleStore` — JSON in Application Support, file `0600` —
/// but held as an injectable `@MainActor ObservableObject` (like `Preferences`)
/// so the panel binds to it live and tests can point it at a temp file.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [String: Note]
    private let url: URL

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
        notes = Self.load(from: url)
    }

    func note(for key: String) -> Note? { notes[key] }

    func text(for key: String) -> String { notes[key]?.text ?? "" }

    /// True only when there's actual content — an all-whitespace note reads as
    /// none, so the dot on a Today row means "there's something written here".
    func hasNote(for key: String) -> Bool {
        !(notes[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Sets a note's text, persisting immediately. Empty (or whitespace-only)
    /// text deletes the note rather than keeping a blank one around.
    func setText(_ text: String, for key: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard notes[key] != nil else { return }
            notes[key] = nil
        } else {
            notes[key] = Note(text: text, updated: Date())
        }
        persist()
    }

    // MARK: Disk

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
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

    private static func load(from url: URL) -> [String: Note] {
        guard let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode([String: Note].self, from: data)
        else { return [:] }
        return notes
    }
}
