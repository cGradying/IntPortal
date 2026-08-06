import Foundation

/// On-disk cache of the scraped grades, so the Grades page renders before the
/// network answers — the same treatment `ScheduleStore` gives the schedule, and
/// for the same reason.
///
/// The student's own grades: Application Support, directory `0700`, file
/// `0600`, cleared on sign-out.
enum GradesStore {
    static let fileURL: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("PUPSISPortal", isDirectory: true)
            .appendingPathComponent("grades.json")
    }()

    static func save(_ report: GradeReport, to url: URL = fileURL) {
        guard let data = try? JSONEncoder().encode(report) else { return }

        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // `.atomic` replaces the file, so re-apply the owner-only mode each write.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// `nil` for "no usable cache" — a missing, unreadable, or stale-format file
    /// is not an error worth surfacing; one refresh rebuilds it.
    static func load(from url: URL = fileURL) -> GradeReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GradeReport.self, from: data)
    }

    static func delete(at url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
