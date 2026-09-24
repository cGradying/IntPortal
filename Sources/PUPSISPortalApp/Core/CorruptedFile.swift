import Foundation

/// Shared by every JSON-document store (`NotesStore`, `SyllabusStore`,
/// `QuizStore`, `GradesStore`, `ScheduleStore`) so a decode failure never
/// turns into data loss. Without this,
/// a file that exists but won't decode was silently treated as "no data yet"
/// — the store then persisted an empty (or partial) document over it on the
/// very next write, and the original content was gone for good.
enum CorruptedFile {
    /// Moves `url` aside to `<name>.corrupt-<yyyyMMdd-HHmmss>` so the bytes
    /// survive for manual recovery. No-op if nothing's there (a missing file
    /// means "no data yet", not corruption).
    ///
    /// ponytail: doesn't also add a "refuse to persist this session" flag —
    /// once the corrupt file is moved aside, the original `url` is free, so
    /// the next persist() can't clobber the quarantined copy (different
    /// filename). Add a suspend flag only if a future caller needs the
    /// in-memory store to stay empty/read-only until an explicit reload.
    @discardableResult
    static func quarantine(_ url: URL, now: Date = Date()) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let stamp = stampFormatter.string(from: now)
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".corrupt-\(stamp)")
        return (try? FileManager.default.moveItem(at: url, to: backup)) != nil
    }

    /// Deletes any quarantined copies of `url` (`<name>.corrupt-*`) — for
    /// stores whose cache is the user's own data and must not outlive
    /// sign-out just because it got renamed aside once.
    static func removeQuarantined(for url: URL) {
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".corrupt-"
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
