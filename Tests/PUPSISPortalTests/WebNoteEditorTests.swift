import XCTest
@testable import PUPSISPortal

/// `strippingOuterMarkdownFence` — the safety net behind the "Structure"/
/// "Create" prompt rules. Confirmed live: a model wrapping its whole reply
/// in an outer ```markdown fence sometimes never closes it, which breaks
/// every line after it once inserted into the note.
final class WebNoteEditorTests: XCTestCase {
    func testStripsAnUnclosedMarkdownFence() {
        let raw = "```markdown\n# Title\n\nBody text."
        XCTAssertEqual(WebNoteEditor.strippingOuterMarkdownFence(raw), "# Title\n\nBody text.")
    }

    func testStripsAProperlyClosedMarkdownFenceToo() {
        let raw = "```markdown\n# Title\n\nBody text.\n```"
        XCTAssertEqual(WebNoteEditor.strippingOuterMarkdownFence(raw), "# Title\n\nBody text.")
    }

    func testStripsAnMdOpenerCaseInsensitively() {
        let raw = "```MD\nJust some text."
        XCTAssertEqual(WebNoteEditor.strippingOuterMarkdownFence(raw), "Just some text.")
    }

    /// A genuinely bare ``` opener (no "markdown"/"md" label) is left
    /// alone — that's a legitimate code sample reply (e.g. "Answer" mode
    /// asked to show a snippet), not the whole-reply-wrapping habit this
    /// exists to catch.
    func testLeavesABareFenceUntouched() {
        let raw = "```\nprint(\"hi\")\n```"
        XCTAssertEqual(WebNoteEditor.strippingOuterMarkdownFence(raw), raw)
    }

    /// A real note that happens to legitimately contain a fenced code
    /// block partway through (per the structure instruction's own rule)
    /// must be untouched — only an *opening* markdown/md fence on the very
    /// first line triggers the strip.
    func testLeavesEmbeddedCodeFencesInTheMiddleUntouched() {
        let raw = "# Notes\n\nSome text.\n\n```python\nprint(1)\n```\n\nMore text."
        XCTAssertEqual(WebNoteEditor.strippingOuterMarkdownFence(raw), raw)
    }

    func testTextWithNoFenceAtAllIsUnchanged() {
        let raw = "# Title\n\nPlain note, no fences."
        XCTAssertEqual(WebNoteEditor.strippingOuterMarkdownFence(raw), raw)
    }
}
