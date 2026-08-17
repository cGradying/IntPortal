import XCTest
@testable import PUPSISPortal

/// Plain-text rendering is pure and easy to pin exactly. PDF writing goes
/// through `NSPrintOperation`/AppKit, so it's verified by hand per the plan
/// rather than unit-tested here — this covers the one real logic path,
/// `Markdown.parse` → plain text.
final class NoteExportTests: XCTestCase {
    func testHeadingsLoseTheHashMarks() {
        XCTAssertEqual(NoteExport.plainText(from: "# Title"), "Title")
    }

    func testBulletsBecomeDots() {
        XCTAssertEqual(NoteExport.plainText(from: "- milk\n- eggs"), "• milk\n• eggs")
    }

    func testCheckboxesBecomeGlyphs() {
        XCTAssertEqual(NoteExport.plainText(from: "- [ ] todo\n- [x] done"), "☐ todo\n☑ done")
    }

    func testParagraphsAndBlankLinesPassThrough() {
        XCTAssertEqual(NoteExport.plainText(from: "one\n\ntwo"), "one\n\ntwo")
    }
}
