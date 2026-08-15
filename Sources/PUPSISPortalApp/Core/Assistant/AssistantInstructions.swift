import Foundation

/// A user-editable "house style" file the assistant reads into its system
/// prompt every turn — how you want notes structured, what to call things,
/// anything else worth it knowing that isn't in the tool catalog. Not a
/// schema, not code: plain text, folded into the prompt the same way
/// `AssistantContext` already is.
///
/// Lives in Application Support next to `notes.json`/`schedule.json` — same
/// convention, same "absent means skip, never guess" behavior those already
/// have. There's no in-app editor for it; `NSWorkspace` opens it in whatever
/// the user's Mac already opens `.md` files with, the same as a "Share as…"
/// export elsewhere in this app.
enum AssistantInstructions {
    static let fileURL: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("assistant-instructions.md")
    }()

    static let defaultTemplate = """
    <!-- The assistant reads this every turn. Delete anything you don't want,
         write in plain language — it's a prompt, not a config format. -->

    When you create or add to a note, prefer short paragraphs and bullet
    points over long blocks of prose.
    """

    /// `nil` when the file doesn't exist or is empty after trimming — the
    /// system prompt skips the section entirely rather than sending a blank
    /// "additional instructions:" heading with nothing under it.
    static func load(from url: URL = fileURL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Creates the file with `defaultTemplate` if it doesn't exist yet, then
    /// returns its URL for `NSWorkspace` to open. Never overwrites an
    /// existing file, even an empty one — that would be a surprising way to
    /// lose an edit.
    static func ensureExists(at url: URL = fileURL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? defaultTemplate.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return url
    }
}
