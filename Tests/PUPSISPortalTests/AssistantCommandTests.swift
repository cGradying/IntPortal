import XCTest
@testable import PUPSISPortal

/// Pure parsing — no store, no model, no actor. `parse` is the seam that
/// keeps slash-commands out of the model's tool-picking loop entirely.
final class AssistantCommandTests: XCTestCase {
    func testPlainProseIsNotACommand() {
        XCTAssertNil(AssistantCommand.parse("what's on my schedule today"))
        XCTAssertNil(AssistantCommand.parse(""))
    }

    func testReadWithQuotedName() {
        XCTAssertEqual(AssistantCommand.parse(#"/read "Physics""#), .read(name: "Physics"))
    }

    func testReadWithBareName() {
        XCTAssertEqual(AssistantCommand.parse("/read Physics"), .read(name: "Physics"))
    }

    func testReadWithNoArgumentFallsBackToOpenNote() {
        XCTAssertEqual(AssistantCommand.parse("/read"), .read(name: nil))
        XCTAssertEqual(AssistantCommand.parse("/read   "), .read(name: nil))
    }

    /// The user's own form: a quoted name that itself starts with a slash.
    func testReadToleratesALeadingSlashInsideQuotes() {
        XCTAssertEqual(AssistantCommand.parse(#"/read "/notes name""#), .read(name: "/notes name"))
    }

    func testSummaryWithQuotedName() {
        XCTAssertEqual(AssistantCommand.parse(#"/summary "Physics Midterm""#), .summary(name: "Physics Midterm"))
    }

    func testSummarizeIsAnAliasForSummary() {
        XCTAssertEqual(AssistantCommand.parse("/summarize Physics"), .summary(name: "Physics"))
    }

    func testCreateTakesTheWholeRestAsThePrompt() {
        XCTAssertEqual(
            AssistantCommand.parse("/create a short note on photosynthesis"),
            .create(prompt: "a short note on photosynthesis")
        )
    }

    func testHelp() {
        XCTAssertEqual(AssistantCommand.parse("/help"), .help)
    }

    func testRagWithQuotedPrompt() {
        XCTAssertEqual(
            AssistantCommand.parse(#"/rag "what does my Sapiens note say about the agricultural revolution?""#),
            .rag(prompt: "what does my Sapiens note say about the agricultural revolution?")
        )
    }

    func testRagWithBarePrompt() {
        XCTAssertEqual(AssistantCommand.parse("/rag what is recursion"), .rag(prompt: "what is recursion"))
    }

    func testCommandNameIsCaseInsensitive() {
        XCTAssertEqual(AssistantCommand.parse("/READ Physics"), .read(name: "Physics"))
    }

    func testUnknownCommandIsNotNil() {
        XCTAssertEqual(AssistantCommand.parse("/frobnicate"), .unknown("frobnicate"))
    }

    // MARK: catalog / Spec — drives the input bar's autocomplete palette

    /// Every real command `parse` understands has a matching catalog entry —
    /// otherwise the autocomplete palette would offer a command, or fail to
    /// offer one, that doesn't match what actually runs.
    func testCatalogCoversEveryParsedCommand() {
        let names = Set(AssistantCommand.catalog.map(\.name))
        XCTAssertEqual(names, ["read", "summary", "create", "rag", "help"])
    }

    func testUsageAddsQuotedParamPlaceholdersOnlyWhenThereAreParams() {
        let read = AssistantCommand.catalog.first { $0.name == "read" }!
        XCTAssertEqual(read.usage, #"/read "name""#)
        let help = AssistantCommand.catalog.first { $0.name == "help" }!
        XCTAssertEqual(help.usage, "/help")
    }

    func testHelpTextListsEveryCommand() {
        for spec in AssistantCommand.catalog {
            XCTAssertTrue(AssistantCommand.helpText.contains("/\(spec.name)"))
        }
    }
}
