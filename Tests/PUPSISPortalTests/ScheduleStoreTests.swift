import XCTest
@testable import PUPSISPortal

/// Everything here writes to a temp directory — never the real
/// Application Support path, which holds the user's actual schedule.
final class ScheduleStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ScheduleStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("schedule.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private let fixture = [
        ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                     faculty: "SANTOS, JUAN", day: .tuesday, start: 14 * 60, end: 16 * 60),
        ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                     faculty: "SANTOS, JUAN", day: .friday, start: 13 * 60 + 30, end: 16 * 60 + 30),
    ]

    func testRoundTripsSessionsAndTimestamp() {
        let stamp = Date(timeIntervalSince1970: 1_754_400_000)
        ScheduleStore.save(fixture, lastUpdated: stamp, to: url)

        let loaded = ScheduleStore.load(from: url)
        XCTAssertEqual(loaded?.sessions, fixture)
        // Encoded as a Double, so compare with a tolerance rather than ==.
        XCTAssertEqual(loaded?.lastUpdated.timeIntervalSince1970 ?? 0,
                       stamp.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Everything the round-trip drops would silently vanish from the UI.
    func testRoundTripKeepsEveryField() {
        ScheduleStore.save(fixture, to: url)
        let loaded = try? XCTUnwrap(ScheduleStore.load(from: url)?.sessions.first)

        XCTAssertEqual(loaded?.subjectCode, "COMP 20073")
        XCTAssertEqual(loaded?.description, "Data Structures")
        XCTAssertEqual(loaded?.faculty, "SANTOS, JUAN")
        XCTAssertEqual(loaded?.day, .tuesday)
        XCTAssertEqual(loaded?.start, 14 * 60)
        XCTAssertEqual(loaded?.end, 16 * 60)
    }

    func testMissingFileLoadsAsNoCacheRatherThanCrashing() {
        XCTAssertNil(ScheduleStore.load(from: url))
    }

    func testCorruptFileLoadsAsNoCache() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        XCTAssertNil(ScheduleStore.load(from: url))
    }

    func testDeleteRemovesTheFileFromDisk() {
        ScheduleStore.save(fixture, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        ScheduleStore.delete(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// The cache holds the student's own schedule; nobody else on the machine
    /// should be able to read it.
    func testCachedScheduleIsOwnerReadableOnly() throws {
        ScheduleStore.save(fixture, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    /// Identity is positional — two decodes of the same session must not
    /// produce different ids, or SwiftUI rebuilds every block on refresh.
    func testIdentityIsStableAcrossDecodes() {
        ScheduleStore.save(fixture, to: url)
        let first = ScheduleStore.load(from: url)?.sessions.map(\.id)
        let second = ScheduleStore.load(from: url)?.sessions.map(\.id)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, fixture.map(\.id))
    }
}
