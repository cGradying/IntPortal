import Foundation

/// Where pasted/dropped note images live on disk. Mirrors `NotesStore`'s disk
/// conventions: Application Support, dir `0700`, file `0600`.
///
/// Lives in Core rather than beside the editor because `NotesStore` has to
/// reach it too — deleting a note deletes the images only that note used.
/// The `pupimg://` scheme handler that reads these back sits in
/// `Views/WebNoteEditor.swift`.
enum NoteImages {
    static let directory: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("note-images", isDirectory: true)
    }()

    /// Decodes `base64` and writes it as a new file; returns the `pupimg://`
    /// URL string to insert into the note, or nil on any I/O failure. The
    /// name is lowercased so it can't mismatch a URL parser that lowercases
    /// the host component.
    static func save(base64: String, ext: String) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let letters = ext.filter(\.isLetter).lowercased()
        let name = "\(UUID().uuidString.lowercased()).\(letters.isEmpty ? "png" : letters)"
        let fileURL = directory.appendingPathComponent(name)
        guard (try? data.write(to: fileURL)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return "pupimg://\(name)"
    }

    static func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    /// Every image filename `text` refers to. Scans for the `pupimg://` scheme
    /// rather than parsing Markdown, because the same reference can appear in a
    /// `![]()` image, a bare link, or raw HTML the editor round-tripped.
    static func referenced(in text: String) -> Set<String> {
        var names: Set<String> = []
        var rest = Substring(text)
        let scheme = "pupimg://"
        while let start = rest.range(of: scheme) {
            let after = rest[start.upperBound...]
            // A filename ends at the first character that can't be in one:
            // the closing paren of a Markdown link, a quote, or whitespace.
            let name = after.prefix { !$0.isWhitespace && $0 != ")" && $0 != "\"" && $0 != "'" && $0 != ">" }
            if !name.isEmpty { names.insert(String(name)) }
            rest = after
        }
        return names
    }

    /// Which image files stop being referenced once `removedKeys` are dropped
    /// from `notes`. The same image can appear in more than one note — the user
    /// can copy the Markdown across — so anything still pointed at survives.
    ///
    /// Pure, and the part worth testing: the deletion below is one call, but
    /// getting this set wrong either leaks files forever or breaks a live note's
    /// image.
    static func orphaned(removing removedKeys: [String], from notes: [String: Note]) -> Set<String> {
        let dropped = removedKeys.reduce(into: Set<String>()) {
            $0.formUnion(referenced(in: notes[$1]?.text ?? ""))
        }
        guard !dropped.isEmpty else { return [] }
        let kept = notes.filter { !removedKeys.contains($0.key) }
        let stillUsed = kept.values.reduce(into: Set<String>()) {
            $0.formUnion(referenced(in: $1.text))
        }
        return dropped.subtracting(stillUsed)
    }

    /// Deletes the named image files. Missing files are not an error — the
    /// point is that they're gone.
    static func delete(_ names: Set<String>) {
        for name in names {
            try? FileManager.default.removeItem(at: url(for: name))
        }
    }

    /// Empties the whole directory — Settings ▸ Misc's "wipe all notes"
    /// action. Unlike `delete(_:)`/`orphaned(removing:from:)`, this isn't
    /// computing what's still referenced; a full wipe means nothing is left
    /// to reference it.
    static func deleteAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
