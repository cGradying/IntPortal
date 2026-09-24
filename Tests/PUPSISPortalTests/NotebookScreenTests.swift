import AppKit
import SwiftUI
import XCTest
@testable import PUPSISPortal

/// `NotebookScreen.vaultDisplayTitle` — the vault, tabs and history must
/// never show a note's raw text (an AI prompt, in particular) as its title.
final class NotebookDisplayTitleTests: XCTestCase {
    func testOverrideWinsOverAHeading() {
        let title = NotebookScreen.vaultDisplayTitle(
            text: "# Actual heading\nbody", override: "User-set title", fallback: "fallback"
        )
        XCTAssertEqual(title, "User-set title")
    }

    /// The bug this exists to fix: a note started from an AI prompt/reply has
    /// no title override, so without this the vault would show the raw first
    /// line of that text (which can be an entire pasted prompt) as its name.
    func testFirstHeadingWinsOverRawTextWhenNoOverride() {
        let prompt = "Summarize the causes of the French Revolution in three bullet points"
        let text = "\(prompt)\n\n## Causes\n- Debt\n- Famine"
        let title = NotebookScreen.vaultDisplayTitle(text: text, override: nil, fallback: "fallback")
        XCTAssertEqual(title, "Causes")
        XCTAssertNotEqual(title, prompt)
    }

    func testFallbackWinsWhenThereIsNoHeadingOrOverride() {
        let title = NotebookScreen.vaultDisplayTitle(text: "just a plain paragraph, no heading", override: nil, fallback: "COMP 001")
        XCTAssertEqual(title, "COMP 001")
    }

    func testBlankOverrideIsTreatedAsNoOverride() {
        let title = NotebookScreen.vaultDisplayTitle(text: "# Real heading", override: "   ", fallback: "fallback")
        XCTAssertEqual(title, "Real heading")
    }

    func testHeadingMarksAreStrippedAndSurroundingWhitespaceTrimmed() {
        let title = NotebookScreen.vaultDisplayTitle(text: "###   Spaced out heading   \nmore text", override: nil, fallback: "fallback")
        XCTAssertEqual(title, "Spaced out heading")
    }

    /// An empty heading line (just `#`s) isn't a usable title — keep scanning
    /// for a real one, then fall back.
    func testEmptyHeadingLineIsSkipped() {
        let title = NotebookScreen.vaultDisplayTitle(text: "#\n\n## Real one", override: nil, fallback: "fallback")
        XCTAssertEqual(title, "Real one")
    }
}

/// Renders `NotebookVault` and `NotebookEditorHeader`/`NotebookEmptyEditorState`
/// in isolation with demo data.
///
/// Deliberately does NOT construct `NotebookScreen` itself or a real
/// `AppState()`: `AppState.init()` (`PUPSISPortalApp.swift`) reads the real
/// Keychain (`credentials = KeychainStore.load()`) whenever the process
/// isn't launched with `-IntPortalDemo`, which a plain `swift test` process
/// never is. Confirmed live, twice — the first `AppState()` built in this
/// suite blocked for ~20 minutes, and a second attempt (sharing one instance
/// across the class to pay that cost at most once) hung indefinitely and had
/// to be killed. That's a real, load-bearing landmine for every future
/// screen's tests, not just this one — worth a fix in `AppState`/
/// `PortalController` (e.g. an injectable or lazy credentials load) by
/// whoever owns `PUPSISPortalApp.swift`, out of this slice's file list.
/// `NotebookVault`, `NotebookEditorHeader` and `NotebookEmptyEditorState`
/// exist as their own `View`s specifically so this suite has something real
/// to render without going anywhere near `AppState`. The full
/// `NotebookScreen` (tabs + `WebNoteEditor`'s `WKWebView`) is exercised by
/// the live launch instead (see the worker report).
@MainActor
final class NotebookSnapshotTests: XCTestCase {
    private var notesURL: URL!

    override func setUp() {
        super.setUp()
        notesURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notebook-snapshot-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: notesURL)
        super.tearDown()
    }

    private func seededNotes() -> NotesStore {
        let notes = NotesStore(url: notesURL)
        let compID = notes.addFolder(name: "COMP 001", to: nil)
        _ = notes.addFile(name: "Number systems", to: compID)
        notes.setText("# Number systems\nBinary, base 2.", for: "class:COMP 001", title: nil)
        notes.setText("Grocery list, milk, eggs", for: "day:2026-09-24", title: nil)
        return notes
    }

    func testVaultRendersInBothRegistrarPalettes() throws {
        // scrolls: false — ImageRenderer can't draw a ScrollView's content.
        let vault = NotebookVault(notes: seededNotes(), selectedKey: .constant(nil), scrolls: false)
        let light = try Snapshot.render(vault, name: "notebook-vault-light", palette: .registrar, scheme: .light)
        let dark = try Snapshot.render(NotebookVault(notes: seededNotes(), selectedKey: .constant(nil), scrolls: false),
                                        name: "notebook-vault-dark", palette: .registrarNight, scheme: .dark)
        XCTAssertGreaterThan(light.size.height, 100)
        XCTAssertGreaterThan(dark.size.height, 100)
    }

    /// A vault file's row highlights action-soft (DESIGN.md) when it's the
    /// open note.
    func testVaultHighlightsTheSelectedNote() throws {
        let notes = seededNotes()
        guard let compFolder = notes.vault.first, let noteNode = compFolder.children?.first, let key = noteNode.noteKey else {
            return XCTFail("expected the seeded COMP 001 / Number systems file")
        }
        let vault = NotebookVault(notes: notes, selectedKey: .constant(key), scrolls: false)
        let image = try Snapshot.render(vault, name: "notebook-vault-selected", palette: .registrar, scheme: .light)
        XCTAssertGreaterThan(image.size.height, 100)
    }

    func testEditorHeaderReadsClassNoteKickerAndTitle() throws {
        let header = NotebookEditorHeader(
            kicker: ("COMP 001 · class note", .init(rgb: 0x1B5DB8)),
            title: .constant("Number systems"),
            meta: "Edited Sep 22 · select any text to Ask AI"
        )
        .padding(20)
        let image = try Snapshot.render(header, name: "notebook-editor-header", palette: .registrar, scheme: .light)
        XCTAssertGreaterThan(image.size.width, 50)
    }

    /// "Pick a note or start one" (spec 04's empty-editor critique fix).
    func testEmptyEditorState() throws {
        let empty = NotebookEmptyEditorState(onNewNote: {}).padding(40)
        let image = try Snapshot.render(empty, name: "notebook-empty", palette: .registrar, scheme: .light)
        XCTAssertGreaterThan(image.size.height, 40)
    }
}
