import Foundation

/// The schedule as it was last scraped, plus when that happened.
struct CachedSchedule: Codable, Equatable {
    let lastUpdated: Date
    let sessions: [ClassSession]
}

/// On-disk cache of the scraped schedule, so a launch can render before the
/// network answers — and keep rendering when it never does.
///
/// Application Support, not the Keychain (this isn't a secret) and not
/// `UserDefaults` (it's a document, not a preference).
enum ScheduleStore {
    static let fileURL: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("schedule.json")
    }()

    static func save(_ sessions: [ClassSession], lastUpdated: Date = Date(), to url: URL = fileURL) {
        let payload = CachedSchedule(lastUpdated: lastUpdated, sessions: sessions)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // The user's own class schedule — readable by them, nobody else on
        // the machine. `.atomic` replaces the file, so re-apply every write.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// `nil` for "no usable cache". A missing, unreadable, or stale-format
    /// file is not an error worth surfacing — one refresh rebuilds it.
    static func load(from url: URL = fileURL) -> CachedSchedule? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedSchedule.self, from: data)
    }

    static func delete(at url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
