import XCTest
@testable import PUPSISPortal

/// `RAGQuery` itself — the pipeline `ask_notes`/`search_notes` and `/rag`
/// both delegate to. Covers the two expected failure modes as typed errors,
/// since both callers switch on them.
@MainActor
final class RAGQueryTests: XCTestCase {
    private var notesURL: URL!
    private var notesStore: NotesStore!

    override func setUpWithError() throws {
        notesURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RAGQueryTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("notes.json")
        notesStore = NotesStore(url: notesURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: notesURL.deletingLastPathComponent())
    }

    func testAskThrowsNoMatchWhenNothingIsInTheVault() async {
        let query = RAGQuery(notes: notesStore)
        do {
            _ = try await query.ask("anything")
            XCTFail("expected .noMatch")
        } catch let error as RAGQuery.QueryError {
            XCTAssertEqual(error, .noMatch("anything"))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testAskThrowsServerUnavailableWhenLlamaServerWontStart() async {
        notesStore.setText("Review recursion.", for: "class:COMP 001")
        let query = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) }),
            ensureServerRunning: { false },
            // Only the llama.cpp path spawns/health-checks a server at all —
            // pin it explicitly, since the default answerer is Ollama-based
            // and wouldn't call ensureServerRunning in the first place.
            answerer: .llamaCpp
        )
        do {
            _ = try await query.ask("recursion")
            XCTFail("expected .serverUnavailable")
        } catch let error as RAGQuery.QueryError {
            XCTAssertEqual(error, .serverUnavailable)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testSearchFallsBackToTermMatchingWhenEmbeddingFails() async {
        notesStore.setText("Review recursion before the exam.", for: "class:COMP 001")
        let query = RAGQuery(notes: notesStore, ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) }))
        let hits = await query.search("recursion")
        XCTAssertEqual(hits.first?.name, "COMP 001")
    }

    func testOnlyRAGIncludedNotesAreSearched() async {
        let key = notesStore.addFile(name: "Excluded", to: nil)
        let id = notesStore.vault.first { $0.noteKey == key }!.id
        notesStore.setText("Review recursion before the exam.", for: key)
        notesStore.setRAGExcluded(true, for: id)

        let query = RAGQuery(notes: notesStore, ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) }))
        let hits = await query.search("recursion")
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: the live bug — a giant single-paragraph note never reached the answer

    /// Reproduces the actual reported bug: a note pasted with zero blank
    /// lines (confirmed live: a real 17.7KB note, `\n\n` count 0) used to
    /// become one oversized chunk that couldn't fit the packing budget and
    /// was silently skipped — the answer came from unrelated smaller notes
    /// instead. With chunking fixed, the big note's own content is what
    /// shows up in `sources`.
    func testAskIncludesAnOversizedSingleParagraphNoteRatherThanDroppingIt() async {
        let bigParagraph = Array(repeating: "Photosynthesis converts light into chemical energy in plants.", count: 300)
            .joined(separator: " ") // one paragraph, no blank lines, ~19000 chars
        notesStore.setText(bigParagraph, for: "class:BIG")
        notesStore.setText("Unrelated shopping list: milk, eggs, bread.", for: "class:DECOY1")
        notesStore.setText("Another unrelated note about the weather today.", for: "class:DECOY2")

        let client = LlamaCppClient(send: { _ in
            (Data(#"{"choices":[{"message":{"content":"Photosynthesis converts light to energy."}}]}"#.utf8), 200)
        })
        let query = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) }),
            llamaCppClient: client,
            ensureServerRunning: { true }, // never spawn/health-check a real llama-server in a test
            answerer: .llamaCpp
        )

        do {
            let answer = try await query.ask("photosynthesis")
            XCTAssertTrue(answer.sources.contains("BIG"))
            XCTAssertFalse(answer.sources.contains("DECOY1"))
            XCTAssertFalse(answer.sources.contains("DECOY2"))
        } catch {
            XCTFail("expected an answer, got \(error)")
        }
    }

    /// The packing-loop half of the fix, isolated: even a single matching
    /// chunk bigger than the whole budget gets truncated to fit, never
    /// dropped outright.
    func testAskTruncatesAnOverBudgetHitInsteadOfDroppingItEntirely() async {
        notesStore.setText("Recursion has a base case and a recursive case, applied repeatedly.", for: "class:COMP 001")
        let client = LlamaCppClient(send: { _ in (Data(#"{"choices":[{"message":{"content":"An answer."}}]}"#.utf8), 200) })
        let query = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) }),
            llamaCppClient: client,
            ensureServerRunning: { true }, // never spawn/health-check a real llama-server in a test
            contextBudget: 20, // smaller than the single matching chunk's own text
            answerer: .llamaCpp
        )

        do {
            let answer = try await query.ask("recursion")
            XCTAssertEqual(answer.sources, ["COMP 001"])
        } catch {
            XCTFail("expected an answer, got \(error)")
        }
    }

    // MARK: Granite as the default answerer — one model, one server, no llama.cpp

    func testAssistantModelAnswererDefaultsToOllamaNotLlamaCpp() async {
        notesStore.setText("Recursion has a base case and a recursive case.", for: "class:COMP 001")
        let query = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(
                // If this ever routes through llamaCppClient instead, the
                // hardcoded 400 below is what fails the test loudly.
                sendChat: { _ in (Data(#"{"message":{"content":"{\"answer\":\"A base case and a recursive case.\"}"}}"#.utf8), 200) },
                sendEmbed: { _ in throw URLError(.notConnectedToInternet) }
            ),
            llamaCppClient: LlamaCppClient(send: { _ in (Data(), 400) }),
            answerModel: "granite4.2:3b"
        )
        do {
            let answer = try await query.ask("recursion")
            XCTAssertEqual(answer.text, "A base case and a recursive case.")
            XCTAssertEqual(answer.sources, ["COMP 001"])
        } catch {
            XCTFail("expected an answer, got \(error)")
        }
    }
}
