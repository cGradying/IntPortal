import XCTest
@testable import PUPSISPortal

/// Everything here writes to a temp directory — never the real
/// Application Support path, which holds the user's actual instructions file.
final class AssistantInstructionsTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AssistantInstructionsTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("assistant-instructions.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testLoadReturnsNilWhenFileDoesNotExist() {
        XCTAssertNil(AssistantInstructions.load(from: url))
    }

    func testLoadReturnsTrimmedContent() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "  Write in short bullet points.  \n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(AssistantInstructions.load(from: url), "Write in short bullet points.")
    }

    /// A file that exists but is only whitespace must read the same as no
    /// file at all — the system prompt has to skip the section either way.
    func testLoadReturnsNilForWhitespaceOnlyFile() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "   \n\n  ".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(AssistantInstructions.load(from: url))
    }

    func testEnsureExistsCreatesTheDefaultTemplate() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        _ = AssistantInstructions.ensureExists(at: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(AssistantInstructions.load(from: url), AssistantInstructions.defaultTemplate)
    }

    /// The whole point of "ensure" rather than "write": a second call must
    /// never clobber something the user already edited.
    func testEnsureExistsNeverOverwritesAnExistingFile() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "My own custom instructions.".write(to: url, atomically: true, encoding: .utf8)
        _ = AssistantInstructions.ensureExists(at: url)
        XCTAssertEqual(AssistantInstructions.load(from: url), "My own custom instructions.")
    }
}
