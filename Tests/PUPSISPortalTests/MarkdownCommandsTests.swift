import XCTest
@testable import PUPSISPortal

/// The pure selection transforms behind the notes toolbar.
final class MarkdownCommandsTests: XCTestCase {
    func testWrapSelection() {
        let r = MarkdownCommands.wrap("read chapter", range: NSRange(location: 5, length: 7), with: "**")
        XCTAssertEqual(r.text, "read **chapter**")
        // Inner text stays selected.
        XCTAssertEqual(r.range, NSRange(location: 7, length: 7))
    }

    func testWrapEmptyDropsCursorBetweenMarkers() {
        let r = MarkdownCommands.wrap("", range: NSRange(location: 0, length: 0), with: "*")
        XCTAssertEqual(r.text, "**")
        XCTAssertEqual(r.range, NSRange(location: 1, length: 0))
    }

    func testToggleChecklistAddsThenRemoves() {
        let text = "buy milk\nwash car"
        let all = NSRange(location: 0, length: (text as NSString).length)

        let added = MarkdownCommands.toggleChecklist(text, range: all)
        XCTAssertEqual(added.text, "- [ ] buy milk\n- [ ] wash car")

        let cleared = MarkdownCommands.toggleChecklist(added.text, range: added.range)
        XCTAssertEqual(cleared.text, "buy milk\nwash car")
    }

    func testToggleNumberedIncrements() {
        let text = "one\ntwo\nthree"
        let all = NSRange(location: 0, length: (text as NSString).length)
        let r = MarkdownCommands.toggleNumbered(text, range: all)
        XCTAssertEqual(r.text, "1. one\n2. two\n3. three")
    }

    func testCycleHeadingRoundTrip() {
        var r = MarkdownCommands.cycleHeading("Title", range: NSRange(location: 0, length: 0))
        XCTAssertEqual(r.text, "# Title")
        r = MarkdownCommands.cycleHeading(r.text, range: NSRange(location: 0, length: 0))
        XCTAssertEqual(r.text, "## Title")
        // Past H6 it clears back to plain text.
        r = MarkdownCommands.cycleHeading("###### Title", range: NSRange(location: 0, length: 0))
        XCTAssertEqual(r.text, "Title")
    }

    func testToggleCheckboxFlipsBothWays() {
        XCTAssertEqual(MarkdownCommands.toggleCheckbox("- [ ] task"), "- [x] task")
        XCTAssertEqual(MarkdownCommands.toggleCheckbox("- [x] task"), "- [ ] task")
        XCTAssertEqual(MarkdownCommands.toggleCheckbox("  - [X] indented"), "  - [ ] indented")
    }

    /// Detection underpins the source round-trip: collapsing these to attachments
    /// and reconstructing must reproduce the exact input, so notes never corrupt.
    func testMathDetectionRoundTrips() {
        let text = "Energy $E=mc^2$ and a block:\n$$\\int_0^1 x\\,dx$$\nprice $5 and $10 stays text."
        let matches = MarkdownCommands.mathMatches(in: text)

        // Two math spans; the currency "$5 and $10" is not one of them.
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].latex, "E=mc^2")
        XCTAssertFalse(matches[0].display)
        XCTAssertEqual(matches[1].latex, "\\int_0^1 x\\,dx")
        XCTAssertTrue(matches[1].display)

        // Reconstruct source from the matches — must equal the original.
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            out += m.display ? "$$\(m.latex)$$" : "$\(m.latex)$"
            cursor = NSMaxRange(m.range)
        }
        out += ns.substring(from: cursor)
        XCTAssertEqual(out, text)
    }

    func testColorWrapsSelection() {
        let r = MarkdownCommands.color("hi", range: NSRange(location: 0, length: 2), hex: "e5484d")
        XCTAssertEqual(r.text, "{#e5484d:hi}")
        XCTAssertEqual(r.range, NSRange(location: 9, length: 2))
    }

    func testColorEmptyDropsCursorInside() {
        let r = MarkdownCommands.color("", range: NSRange(location: 0, length: 0), hex: "2f9e44")
        XCTAssertEqual(r.text, "{#2f9e44:}")
        XCTAssertEqual(r.range, NSRange(location: 9, length: 0))
    }

    func testLinkPlacesCursorOnPlaceholder() {
        let r = MarkdownCommands.link("docs", range: NSRange(location: 0, length: 4))
        XCTAssertEqual(r.text, "[docs](url)")
        XCTAssertEqual(r.range, NSRange(location: 7, length: 3))
    }
}
