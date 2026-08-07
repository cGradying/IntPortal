import Foundation

/// On-disk cache of the scraped grades, so the Grades page renders before the
/// network answers — the same treatment `ScheduleStore` gives the schedule, and
/// for the same reason.
///
/// The student's own grades: Application Support, directory `0700`, file
/// `0600`, cleared on sign-out.
enum GradesStore {
    private static let directory: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PUPSISPortal", isDirectory: true)
    }()

    static let fileURL = directory.appendingPathComponent("grades.json")
    /// Past terms, backfilled from the grades page's SY/Semester dropdowns.
    /// Same treatment as the current term — the student's own data, `0600`.
    static let historyURL = directory.appendingPathComponent("grades-history.json")

    static func save(_ report: GradeReport, to url: URL = fileURL) {
        write(report, to: url)
    }

    static func saveHistory(_ reports: [GradeReport], to url: URL = historyURL) {
        write(reports, to: url)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
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

    static func loadHistory(from url: URL = historyURL) -> [GradeReport] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([GradeReport].self, from: data)) ?? []
    }

    /// Clears **both** the current-term cache and the history — sign-out has to
    /// take all of the student's grades off disk, not just the visible one.
    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: historyURL)
    }

    /// Fold one term's snapshot into the history: replace any existing entry for
    /// the same term, keep the rest, and return it sorted oldest-first so the
    /// trend never depends on the order terms were scraped in.
    static func merged(_ report: GradeReport, into history: [GradeReport]) -> [GradeReport] {
        var out = history.filter { $0.termLabel != report.termLabel }
        out.append(report)
        return out.sorted { $0.termOrder < $1.termOrder }
    }
}
