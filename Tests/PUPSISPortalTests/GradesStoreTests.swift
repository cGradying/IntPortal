import XCTest
@testable import PUPSISPortal

/// Everything here writes to a temp directory — never the real Application
/// Support path, which holds the user's actual grades.
final class GradesStoreTests: XCTestCase {
    private var fileURL: URL!
    private var historyURL: URL!

    override func setUpWithError() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GradesStoreTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("grades.json")
        historyURL = directory.appendingPathComponent("grades-history.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func report(sy: String = "2025-2026", sem: String = "1st Semester") -> GradeReport {
        GradeReport(
            lastUpdated: Date(timeIntervalSince1970: 1_754_400_000),
            subjects: [], summary: [:], schoolYear: sy, semester: sem
        )
    }

    private func quarantined(for url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") }
    }

    // MARK: Corruption — current-term file

    /// A corrupt grades.json used to load as "no grades" and then get
    /// overwritten by the very next save. It must be moved aside instead.
    func testCorruptGradesFileIsQuarantinedAndNotClobberedByTheNextSave() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: fileURL)

        XCTAssertNil(GradesStore.load(from: fileURL))

        let found = try quarantined(for: fileURL)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(try Data(contentsOf: found[0]), Data("not valid json".utf8))

        // The next save must write only to the original path, never touch
        // the quarantined copy.
        GradesStore.save(report(), to: fileURL)
        XCTAssertEqual(try Data(contentsOf: found[0]), Data("not valid json".utf8))
        XCTAssertNotNil(GradesStore.load(from: fileURL))
    }

    // MARK: Corruption — history file

    func testCorruptHistoryFileIsQuarantinedAndNotClobberedByTheNextSave() throws {
        try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("also not json".utf8).write(to: historyURL)

        XCTAssertEqual(GradesStore.loadHistory(from: historyURL), [])

        let found = try quarantined(for: historyURL)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(try Data(contentsOf: found[0]), Data("also not json".utf8))

        GradesStore.saveHistory([report()], to: historyURL)
        XCTAssertEqual(try Data(contentsOf: found[0]), Data("also not json".utf8))
        XCTAssertEqual(GradesStore.loadHistory(from: historyURL).count, 1)
    }

    // MARK: Sign-out

    /// `delete()` is the student's own data leaving the machine on sign-out —
    /// a quarantined copy from an earlier corruption must go with it.
    func testDeleteRemovesQuarantinedCopiesToo() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: fileURL)
        try Data("bad".utf8).write(to: historyURL)
        XCTAssertNil(GradesStore.load(from: fileURL))
        XCTAssertEqual(GradesStore.loadHistory(from: historyURL), [])
        XCTAssertEqual(try quarantined(for: fileURL).count, 1)
        XCTAssertEqual(try quarantined(for: historyURL).count, 1)

        GradesStore.save(report(), to: fileURL)
        GradesStore.saveHistory([report()], to: historyURL)

        GradesStore.delete(fileURL: fileURL, historyURL: historyURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertEqual(try quarantined(for: fileURL).count, 0)
        XCTAssertEqual(try quarantined(for: historyURL).count, 0)
    }

    func testMissingFileNeverQuarantines() throws {
        XCTAssertNil(GradesStore.load(from: fileURL))
        // No directory even exists yet — quarantine must be a clean no-op.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
    }
}
