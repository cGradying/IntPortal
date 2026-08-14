import XCTest
@testable import PUPSISPortal

/// Pure logic only — nothing here touches `NoteImages.directory`, which points
/// at the user's real Application Support folder.
final class NoteImagesTests: XCTestCase {

    private func note(_ text: String) -> Note {
        Note(text: text, updated: Date(timeIntervalSince1970: 0), title: nil)
    }

    // MARK: referenced(in:)

    func testFindsMarkdownImageReference() {
        let names = NoteImages.referenced(in: "before ![](pupimg://abc.png) after")
        XCTAssertEqual(names, ["abc.png"])
    }

    func testFindsSeveralReferences() {
        let text = "![](pupimg://a.png)\n\ntext\n\n![](pupimg://b.jpeg)"
        XCTAssertEqual(NoteImages.referenced(in: text), ["a.png", "b.jpeg"])
    }

    func testDeduplicatesRepeatedReference() {
        let text = "![](pupimg://a.png) and again ![](pupimg://a.png)"
        XCTAssertEqual(NoteImages.referenced(in: text), ["a.png"])
    }

    /// The editor round-trips raw HTML, so a reference can arrive quoted.
    func testFindsReferenceInQuotedHTML() {
        XCTAssertEqual(NoteImages.referenced(in: #"<img src="pupimg://a.png">"#), ["a.png"])
        XCTAssertEqual(NoteImages.referenced(in: "<img src='pupimg://b.png'>"), ["b.png"])
    }

    func testFindsBareReference() {
        XCTAssertEqual(NoteImages.referenced(in: "see pupimg://a.png here"), ["a.png"])
    }

    func testNoReferencesInPlainText() {
        XCTAssertEqual(NoteImages.referenced(in: "just some notes about pupimg"), [])
    }

    func testEmptyTextHasNoReferences() {
        XCTAssertEqual(NoteImages.referenced(in: ""), [])
    }

    // MARK: orphaned(removing:from:)

    func testDeletedNotesImageIsOrphaned() {
        let notes = ["vault:1": note("![](pupimg://a.png)")]
        XCTAssertEqual(NoteImages.orphaned(removing: ["vault:1"], from: notes), ["a.png"])
    }

    /// The whole point of the reference check: copying the Markdown into a
    /// second note must keep the file alive when the first note goes.
    func testImageStillUsedElsewhereSurvives() {
        let notes = [
            "vault:1": note("![](pupimg://shared.png)"),
            "vault:2": note("also ![](pupimg://shared.png)"),
        ]
        XCTAssertEqual(NoteImages.orphaned(removing: ["vault:1"], from: notes), [])
    }

    func testOnlyTheUnsharedImagesAreOrphaned() {
        let notes = [
            "vault:1": note("![](pupimg://shared.png) ![](pupimg://only-mine.png)"),
            "vault:2": note("![](pupimg://shared.png)"),
        ]
        XCTAssertEqual(NoteImages.orphaned(removing: ["vault:1"], from: notes), ["only-mine.png"])
    }

    func testDeletingAFolderOrphansEveryChildsImages() {
        let notes = [
            "vault:1": note("![](pupimg://a.png)"),
            "vault:2": note("![](pupimg://b.png)"),
            "vault:3": note("untouched"),
        ]
        XCTAssertEqual(NoteImages.orphaned(removing: ["vault:1", "vault:2"], from: notes),
                       ["a.png", "b.png"])
    }

    func testNoteWithoutImagesOrphansNothing() {
        let notes = ["vault:1": note("plain text")]
        XCTAssertEqual(NoteImages.orphaned(removing: ["vault:1"], from: notes), [])
    }

    func testRemovingMissingKeyOrphansNothing() {
        let notes = ["vault:1": note("![](pupimg://a.png)")]
        XCTAssertEqual(NoteImages.orphaned(removing: ["vault:nope"], from: notes), [])
    }
}
