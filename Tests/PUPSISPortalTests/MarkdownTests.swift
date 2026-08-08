import XCTest
@testable import PUPSISPortal

/// The line-based Markdown block splitter behind the popup notes preview.
final class MarkdownTests: XCTestCase {
    func testHeadingLevels() {
        XCTAssertEqual(Markdown.parse("# Title"), [.heading(level: 1, text: "Title")])
        XCTAssertEqual(Markdown.parse("### Deep"), [.heading(level: 3, text: "Deep")])
    }

    /// Seven hashes isn't a heading, and a hash with no space is just text.
    func testNonHeadings() {
        XCTAssertEqual(Markdown.parse("####### too many"), [.paragraph(text: "####### too many")])
        XCTAssertEqual(Markdown.parse("#nospace"), [.paragraph(text: "#nospace")])
    }

    func testBullets() {
        XCTAssertEqual(Markdown.parse("- milk"), [.bullet(text: "milk")])
        XCTAssertEqual(Markdown.parse("* eggs"), [.bullet(text: "eggs")])
    }

    func testCheckboxes() {
        XCTAssertEqual(Markdown.parse("- [ ] todo"), [.checkbox(done: false, text: "todo")])
        XCTAssertEqual(Markdown.parse("- [x] done"), [.checkbox(done: true, text: "done")])
        XCTAssertEqual(Markdown.parse("- [X] done"), [.checkbox(done: true, text: "done")])
    }

    func testBlankLinesAndParagraphs() {
        XCTAssertEqual(
            Markdown.parse("hello\n\nworld"),
            [.paragraph(text: "hello"), .blank, .paragraph(text: "world")]
        )
    }

    func testMixedDocument() {
        let doc = "# Chem\n- [ ] lab report\n- read ch. 4\nnote: **bold** stays inline"
        XCTAssertEqual(Markdown.parse(doc), [
            .heading(level: 1, text: "Chem"),
            .checkbox(done: false, text: "lab report"),
            .bullet(text: "read ch. 4"),
            .paragraph(text: "note: **bold** stays inline"),
        ])
    }
}
