import XCTest
@testable import PUPSISPortal

/// `.docx`/`.pptx` are just zips of XML — rather than check a binary fixture
/// into the repo, these build a minimal synthetic archive at test time with
/// `/usr/bin/zip` (present on every macOS install, same tool `OPCContainer`
/// itself shells out to `unzip` from) and tear it down after.
final class OPCContainerTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func zip(_ entries: [String: String]) throws -> URL {
        for (name, content) in entries {
            let path = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: path, atomically: true, encoding: .utf8)
        }
        let archive = dir.appendingPathComponent("out.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = dir
        process.arguments = ["-r", "-q", archive.lastPathComponent] + entries.keys.map { $0 }
        try process.run()
        process.waitUntilExit()
        return archive
    }

    // MARK: docx

    func testDocxExtractsTextRunsAndInsertsParagraphBreaks() throws {
        let xml = """
        <w:document xmlns:w="ns"><w:body>
        <w:p><w:r><w:t>First paragraph.</w:t></w:r></w:p>
        <w:p><w:r><w:t>Second </w:t></w:r><w:r><w:t>paragraph.</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let url = try zip(["word/document.xml": xml])

        let text = try OPCContainer.docxText(from: url)

        XCTAssertEqual(text, "First paragraph.\nSecond paragraph.")
    }

    func testDocxWithNoTextThrowsNoExtractableText() throws {
        let xml = #"<w:document xmlns:w="ns"><w:body><w:p></w:p></w:body></w:document>"#
        let url = try zip(["word/document.xml": xml])

        XCTAssertThrowsError(try OPCContainer.docxText(from: url)) { error in
            XCTAssertEqual(error as? OPCContainer.ExtractError, .noExtractableText)
        }
    }

    func testMissingDocumentPartThrowsUnreadable() throws {
        let url = try zip(["other.txt": "not a docx"])

        XCTAssertThrowsError(try OPCContainer.docxText(from: url)) { error in
            XCTAssertEqual(error as? OPCContainer.ExtractError, .unreadable)
        }
    }

    // MARK: pptx

    func testPptxJoinsSlidesInNumericOrderNotLexicographicOrder() throws {
        // slide10 must sort after slide2, not before it.
        let slide2 = #"<p:sld xmlns:a="ns"><a:p><a:r><a:t>Slide two</a:t></a:r></a:p></p:sld>"#
        let slide10 = #"<p:sld xmlns:a="ns"><a:p><a:r><a:t>Slide ten</a:t></a:r></a:p></p:sld>"#
        let url = try zip([
            "ppt/slides/slide2.xml": slide2,
            "ppt/slides/slide10.xml": slide10,
        ])

        let text = try OPCContainer.pptxText(from: url)

        XCTAssertEqual(text, "Slide two\n\nSlide ten")
    }

    func testPptxWithNoSlidesThrowsNoExtractableText() throws {
        let url = try zip(["other.txt": "not a pptx"])

        XCTAssertThrowsError(try OPCContainer.pptxText(from: url)) { error in
            XCTAssertEqual(error as? OPCContainer.ExtractError, .noExtractableText)
        }
    }
}

extension OPCContainer.ExtractError: Equatable {
    public static func == (lhs: OPCContainer.ExtractError, rhs: OPCContainer.ExtractError) -> Bool {
        switch (lhs, rhs) {
        case (.unreadable, .unreadable), (.noExtractableText, .noExtractableText): true
        default: false
        }
    }
}
