import XCTest
@testable import PUPSISPortal

/// Every case drives generation through an injected `LlamaCppClient` — no
/// network, no real llama-server needed for this suite to pass. Source is always
/// `.material`, so no `RAGQuery`/vault is involved either.
@MainActor
final class CardGeneratorTests: XCTestCase {
    /// Two paragraphs, each under `twoChunkSize` on its own (so neither gets
    /// hard-split) but too big to combine with the other into one chunk —
    /// `NoteRetrieval.chunks` reliably turns this into exactly two chunks.
    private static let twoChunkSize = 100
    private static let twoChunkText =
        String(repeating: "a", count: 80) + "\n\n" + String(repeating: "b", count: 80)

    private func envelope(_ content: String) -> (Data, Int) {
        let wrapper: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        return ((try? JSONSerialization.data(withJSONObject: wrapper)) ?? Data(), 200)
    }

    private func cardsJSON(_ cards: [(front: String, back: String, subject: String?)]) -> String {
        let array = cards.map { c -> [String: Any] in
            var dict: [String: Any] = ["front": c.front, "back": c.back]
            if let subject = c.subject { dict["subject"] = subject }
            return dict
        }
        let data = try! JSONSerialization.data(withJSONObject: ["cards": array])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: Basic decode + citation

    func testDecodesCardsAndAttachesTheChunkAsCitation() async {
        let client = LlamaCppClient(send: { _ in self.envelope(self.cardsJSON([(front: "Q1", back: "A1", subject: "Bio")])) })

        let result = await CardGenerator.run(
            source: .material(text: "Photosynthesis converts light into chemical energy.", label: "Bio notes"),
            model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards.first?.front, "Q1")
        XCTAssertEqual(result.cards.first?.subject, "Bio")
        XCTAssertEqual(result.cards.first?.citation, "Bio notes")
        XCTAssertEqual(result.failedChunks, 0)
    }

    /// The model didn't emit a subject — falls back to the chunk's own name
    /// rather than an empty string, since `subject` must never be blank.
    func testMissingSubjectFallsBackToTheChunkName() async {
        let client = LlamaCppClient(send: { _ in self.envelope(self.cardsJSON([(front: "Q1", back: "A1", subject: nil)])) })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "Untitled material"),
            model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.cards.first?.subject, "Untitled material")
    }

    // MARK: The control-character salvage case

    /// Same failure `AssistantEngine` found: a model that writes a literal
    /// newline inside a JSON string breaks `JSONDecoder` unless it's escaped
    /// first. Confirms `CardGenerator` reuses that fix rather than choking on it.
    func testSalvagesALiteralNewlineInsideAStringField() async {
        let raw = "{\"cards\":[{\"front\":\"Q1\",\"back\":\"line one\nline two\",\"subject\":\"S\"}]}"
        let client = LlamaCppClient(send: { _ in self.envelope(raw) })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "L"),
            model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.cards.count, 1)
        XCTAssertTrue(result.cards.first?.back.contains("line one") ?? false)
    }

    // MARK: Partial-failure retention

    /// Two chunks, one throws — the cards from the chunk that succeeded must
    /// survive, not be discarded because a sibling call failed. Mirrors
    /// `OllamaClient`'s own `stream:false`/no-retry behavior: a single failed
    /// request must not cost work that already completed.
    /// Content-keyed rather than call-count-keyed: the "a" chunk throws every
    /// time it's asked, including on the halved-count retry, so this stays
    /// true regardless of how many attempts a failing chunk gets.
    func testKeepsCardsFromSucceedingChunksWhenAnotherChunkFailsEvenAfterItsRetry() async {
        struct Boom: Error {}
        let client = LlamaCppClient(send: { body in
            if self.userContent(of: body).contains("aaaa") { throw Boom() }
            return self.envelope(self.cardsJSON([(front: "Q-from-b-chunk", back: "A", subject: "S")]))
        })

        let result = await CardGenerator.run(
            source: .material(text: Self.twoChunkText, label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: Self.twoChunkSize,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.totalChunks, 2)
        XCTAssertEqual(result.failedChunks, 1, "the a-chunk fails its retry too, since it always throws")
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards.first?.front, "Q-from-b-chunk")
    }

    // MARK: Truncation retry

    /// The failure this whole pass exists to fix: a reply cut off mid-array
    /// (the model ran out of its output budget) decodes as invalid JSON, but
    /// a second attempt at half the requested count succeeds.
    func testTruncatedReplyRecoversOnTheHalvedRetry() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            if callCount == 1 { return self.envelope(#"{"cards":[{"front":"Q1","back":"A1","subject":"S"#) } // cut off mid-object
            return self.envelope(self.cardsJSON([(front: "Recovered", back: "A", subject: "S")]))
        })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 2, "one initial attempt, one retry")
        XCTAssertEqual(result.failedChunks, 0)
        XCTAssertEqual(result.cards.first?.front, "Recovered")
    }

    /// Genuinely broken output (not just truncated) fails both the original
    /// attempt and the retry — the chunk is counted as failed, same as
    /// before this pass, rather than retried forever.
    func testGarbageReplyFailsBothAttemptsAndCountsAsFailed() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in callCount += 1; return self.envelope("not json at all") })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.failedChunks, 1)
        XCTAssertTrue(result.cards.isEmpty)
    }

    // MARK: acceptedAnswers

    func testAcceptedAnswersDecodeOntoTheCard() async {
        let raw = #"{"cards":[{"front":"Q1","back":"A1","subject":"S","acceptedAnswers":["Alt 1","Alt 2"]}]}"#
        let client = LlamaCppClient(send: { _ in self.envelope(raw) })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.cards.first?.acceptedAnswers, ["Alt 1", "Alt 2"])
    }

    /// A reply that omits the field entirely (an older prompt, or a model
    /// that ignored the instruction) still decodes — the field is optional
    /// in the schema, not required.
    func testMissingAcceptedAnswersFieldStillDecodes() async {
        let client = LlamaCppClient(send: { _ in self.envelope(self.cardsJSON([(front: "Q1", back: "A1", subject: "S")])) })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertNil(result.cards.first?.acceptedAnswers)
    }

    func testBlankAcceptedAnswersAreDroppedNotKeptAsEmptyStrings() async {
        let raw = #"{"cards":[{"front":"Q1","back":"A1","subject":"S","acceptedAnswers":["  ","Real one"]}]}"#
        let client = LlamaCppClient(send: { _ in self.envelope(raw) })

        let result = await CardGenerator.run(
            source: .material(text: "Some material.", label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.cards.first?.acceptedAnswers, ["Real one"])
    }

    // MARK: num_predict sizing

    func testNumPredictScalesWithRequestedCountAndCapsAt4096() {
        XCTAssertEqual(CardGenerator.numPredict(for: 5), 190 * 5 + 200)
        XCTAssertEqual(CardGenerator.numPredict(for: 1000), 4096)
    }

    // MARK: Material chunk cap

    func testOversizedMaterialIsCappedAndReportsTruncation() async {
        // 15 paragraphs, each too big to combine with a neighbor under this
        // chunk size, so this reliably becomes 15 chunks before the cap.
        let text = (0..<15).map { String(repeating: "p\($0)", count: 12) }.joined(separator: "\n\n")
        let client = LlamaCppClient(send: { _ in self.envelope(self.cardsJSON([])) })

        let result = await CardGenerator.run(
            source: .material(text: text, label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 40,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.totalChunks, CardGenerator.maxChunksPerRun)
        XCTAssertTrue(result.truncatedMaterial)
    }

    func testMaterialUnderTheCapIsNotReportedAsTruncated() async {
        let client = LlamaCppClient(send: { _ in self.envelope(self.cardsJSON([])) })

        let result = await CardGenerator.run(
            source: .material(text: Self.twoChunkText, label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: Self.twoChunkSize,
            ensureServerRunning: { true }
        )

        XCTAssertFalse(result.truncatedMaterial)
    }

    private func userContent(of body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let user = messages.first(where: { ($0["role"] as? String) == "user" })?["content"] as? String
        else { return "" }
        return user
    }

    func testEmptyMaterialProducesNoChunksAndNoRequests() async {
        var called = false
        let client = LlamaCppClient(send: { _ in called = true; return self.envelope(self.cardsJSON([])) })

        let result = await CardGenerator.run(
            source: .material(text: "   \n\n  ", label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 700,
            ensureServerRunning: { true }
        )

        XCTAssertFalse(called)
        XCTAssertEqual(result.totalChunks, 0)
        XCTAssertTrue(result.cards.isEmpty)
    }

    // MARK: Cross-chunk dedupe

    func testDedupesCardsWithTheSameFrontAcrossChunksCaseAndWhitespaceInsensitively() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            let front = callCount == 1 ? "What is X?" : "  what IS x?  "
            return self.envelope(self.cardsJSON([(front: front, back: "A\(callCount)", subject: "S")]))
        })

        let result = await CardGenerator.run(
            source: .material(text: Self.twoChunkText, label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: Self.twoChunkSize,
            ensureServerRunning: { true }
        )

        XCTAssertEqual(result.totalChunks, 2)
        XCTAssertEqual(result.cards.count, 1, "the second chunk's near-duplicate front must be dropped")
    }

    // MARK: Cancellation

    func testCancellationStopsBeforeLaterChunksAreRequested() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            return self.envelope(self.cardsJSON([(front: "Q\(callCount)", back: "A", subject: "S")]))
        })

        let text = String(repeating: "First paragraph fact. ", count: 40)
            + "\n\n" + String(repeating: "Second paragraph fact. ", count: 40)

        let result = await CardGenerator.run(
            source: .material(text: text, label: "L"), model: "m", client: client, ragQuery: nil, chunkSize: 200,
            isCancelled: { true },
            ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(result.cards.isEmpty)
    }
}
