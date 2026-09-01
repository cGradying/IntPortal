import XCTest
@testable import PUPSISPortal

/// Every case drives extraction through an injected `LlamaCppClient` — no
/// network, no real llama-server needed for this suite to pass. Same shape
/// as `CardGeneratorTests`.
@MainActor
final class SyllabusExtractorTests: XCTestCase {
    private static let twoChunkSize = 100
    private static let twoChunkText =
        String(repeating: "a", count: 80) + "\n\n" + String(repeating: "b", count: 80)

    private let calendar = Calendar.current
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func envelope(_ content: String) -> (Data, Int) {
        let wrapper: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        return ((try? JSONSerialization.data(withJSONObject: wrapper)) ?? Data(), 200)
    }

    private func itemsJSON(
        _ items: [(week: Int?, topic: String, date: String?, type: String)],
        gradingComponents: [(name: String, weight: Double)] = []
    ) -> String {
        let array = items.map { i -> [String: Any] in
            var dict: [String: Any] = ["topic": i.topic, "type": i.type]
            if let week = i.week { dict["week"] = week }
            if let date = i.date { dict["date"] = date }
            return dict
        }
        var payload: [String: Any] = ["items": array]
        if !gradingComponents.isEmpty {
            payload["gradingComponents"] = gradingComponents.map { ["name": $0.name, "weight": $0.weight] }
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: Week → date mapping

    func testWeekMapsOntoTermStartSevenDaysPerWeek() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: 3, topic: "Chain rule", date: nil, type: "lecture")]))
        })
        let termStart = date(2026, 8, 10) // a Monday

        let result = await SyllabusExtractor.run(
            source: .material(text: "Week 3: Chain rule", label: "L"), subjectCode: "MATH01", termStart: termStart,
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.items.first?.date, calendar.date(byAdding: .day, value: 14, to: termStart))
    }

    func testNoWeekAndNoDateLeavesDateNil() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: nil, topic: "Intro", date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Intro", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertNil(result.items.first?.date)
    }

    /// A literal date the source text actually printed wins over the
    /// week-number math — the model is trusted to *copy* a real date, never
    /// to compute one.
    func testLiteralDateWinsOverWeekMath() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: 3, topic: "Midterm", date: "2026-09-01", type: "exam")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Midterm on Sept 1", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.items.first?.date, date(2026, 9, 1))
    }

    func testUnparsableLiteralDateFallsBackToWeekMath() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: 1, topic: "Intro", date: "not a date", type: "lecture")]))
        })
        let termStart = date(2026, 8, 10)

        let result = await SyllabusExtractor.run(
            source: .material(text: "Intro", label: "L"), subjectCode: "MATH01", termStart: termStart,
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.items.first?.date, termStart)
    }

    // MARK: source tagging

    func testMaterialSourceTagsItemsAsImported() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: 1, topic: "Intro", date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Intro", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.items.first?.source, .imported)
    }

    func testFromScratchSourceTagsItemsAsGeneratedAndSkipsChunking() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            return self.envelope(self.itemsJSON([(week: 1, topic: "Intro", date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .fromScratch(description: "MATH01 — intro course"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(result.totalChunks, 1)
        XCTAssertEqual(result.items.first?.source, .generated)
    }

    // MARK: Partial-failure retention

    func testKeepsItemsFromSucceedingChunksWhenAnotherChunkFailsEvenAfterItsRetry() async {
        struct Boom: Error {}
        let client = LlamaCppClient(send: { body in
            if self.userContent(of: body).contains("aaaa") { throw Boom() }
            return self.envelope(self.itemsJSON([(week: 1, topic: "From b chunk", date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: Self.twoChunkText, label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: Self.twoChunkSize, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.totalChunks, 2)
        XCTAssertEqual(result.failedChunks, 1)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.topic, "From b chunk")
    }

    // MARK: Truncation retry

    func testTruncatedReplyRecoversOnTheHalvedRetry() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            if callCount == 1 { return self.envelope(#"{"items":[{"topic":"Cut off","type":"lectur"#) }
            return self.envelope(self.itemsJSON([(week: 1, topic: "Recovered", date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Some material.", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.failedChunks, 0)
        XCTAssertEqual(result.items.first?.topic, "Recovered")
    }

    func testGarbageReplyFailsBothAttemptsAndCountsAsFailed() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in callCount += 1; return self.envelope("not json at all") })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Some material.", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.failedChunks, 1)
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: Dedupe

    func testDedupesSameWeekAndTopicAcrossChunksCaseAndWhitespaceInsensitively() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            let topic = callCount == 1 ? "Chain rule" : "  chain RULE  "
            return self.envelope(self.itemsJSON([(week: 3, topic: topic, date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: Self.twoChunkText, label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: Self.twoChunkSize, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.totalChunks, 2)
        XCTAssertEqual(result.items.count, 1)
    }

    // MARK: Material chunk cap

    func testOversizedMaterialIsCappedAndReportsTruncation() async {
        let text = (0..<15).map { String(repeating: "p\($0)", count: 12) }.joined(separator: "\n\n")
        let client = LlamaCppClient(send: { _ in self.envelope(self.itemsJSON([])) })

        let result = await SyllabusExtractor.run(
            source: .material(text: text, label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 40, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.totalChunks, SyllabusExtractor.maxChunksPerRun)
        XCTAssertTrue(result.truncatedMaterial)
    }

    func testEmptyMaterialProducesNoChunksAndNoRequests() async {
        var called = false
        let client = LlamaCppClient(send: { _ in called = true; return self.envelope(self.itemsJSON([])) })

        let result = await SyllabusExtractor.run(
            source: .material(text: "   \n\n  ", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertFalse(called)
        XCTAssertEqual(result.totalChunks, 0)
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: type fallback

    func testUnknownTypeFallsBackToLecture() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: 1, topic: "Intro", date: nil, type: "bogus")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Intro", label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.items.first?.type, .lecture)
    }

    // MARK: Grading components

    func testGradingComponentsAreExtractedFromMaterial() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON(
                [(week: 1, topic: "Intro", date: nil, type: "lecture")],
                gradingComponents: [("Midterm", 30), ("Final", 70)]
            ))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Grading: Midterm 30%, Final 70%", label: "L"), subjectCode: "MATH01",
            termStart: date(2026, 8, 10), model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.gradingComponents.map(\.name), ["Midterm", "Final"])
        XCTAssertEqual(result.gradingComponents.map(\.weight), [30, 70])
        XCTAssertTrue(result.gradingComponents.allSatisfy { $0.score == nil })
    }

    /// Only the first chunk that reports a non-empty breakdown wins — a
    /// second chunk's (empty, or a re-statement) is ignored rather than
    /// appended as duplicates.
    func testOnlyTheFirstChunkWithGradingComponentsIsKept() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            if callCount == 1 {
                return self.envelope(self.itemsJSON(
                    [(week: 1, topic: "From a", date: nil, type: "lecture")],
                    gradingComponents: [("Midterm", 30)]
                ))
            }
            return self.envelope(self.itemsJSON(
                [(week: 2, topic: "From b", date: nil, type: "lecture")],
                gradingComponents: [("Should be ignored", 99)]
            ))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: Self.twoChunkText, label: "L"), subjectCode: "MATH01",
            termStart: date(2026, 8, 10), model: "m", client: client, chunkSize: Self.twoChunkSize, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.gradingComponents.map(\.name), ["Midterm"])
    }

    /// A from-scratch run never trusts a grading breakdown — those weights
    /// would be entirely invented, unlike the (clearly labeled generated)
    /// topics themselves.
    func testFromScratchNeverReturnsGradingComponentsEvenIfTheModelEmitsThem() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON(
                [(week: 1, topic: "Intro", date: nil, type: "lecture")],
                gradingComponents: [("Made up", 100)]
            ))
        })

        let result = await SyllabusExtractor.run(
            source: .fromScratch(description: "MATH01 — intro course"), subjectCode: "MATH01",
            termStart: date(2026, 8, 10), model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertTrue(result.gradingComponents.isEmpty)
    }

    func testBlankOrZeroWeightComponentsAreDropped() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON(
                [(week: 1, topic: "Intro", date: nil, type: "lecture")],
                gradingComponents: [("  ", 30), ("Final", 0), ("Real", 70)]
            ))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Intro", label: "L"), subjectCode: "MATH01",
            termStart: date(2026, 8, 10), model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertEqual(result.gradingComponents.map(\.name), ["Real"])
    }

    func testNoGradingComponentsFieldInReplyLeavesResultEmpty() async {
        let client = LlamaCppClient(send: { _ in
            self.envelope(self.itemsJSON([(week: 1, topic: "Intro", date: nil, type: "lecture")]))
        })

        let result = await SyllabusExtractor.run(
            source: .material(text: "Intro", label: "L"), subjectCode: "MATH01",
            termStart: date(2026, 8, 10), model: "m", client: client, chunkSize: 700, ensureServerRunning: { true }
        )

        XCTAssertTrue(result.gradingComponents.isEmpty)
    }

    // MARK: Cancellation

    func testCancellationStopsBeforeLaterChunksAreRequested() async {
        var callCount = 0
        let client = LlamaCppClient(send: { _ in
            callCount += 1
            return self.envelope(self.itemsJSON([(week: 1, topic: "Q\(callCount)", date: nil, type: "lecture")]))
        })
        let text = String(repeating: "First paragraph fact. ", count: 40)
            + "\n\n" + String(repeating: "Second paragraph fact. ", count: 40)

        let result = await SyllabusExtractor.run(
            source: .material(text: text, label: "L"), subjectCode: "MATH01", termStart: date(2026, 8, 10),
            model: "m", client: client, chunkSize: 200, isCancelled: { true }, ensureServerRunning: { true }
        )

        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(result.items.isEmpty)
    }

    private func userContent(of body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let user = messages.first(where: { ($0["role"] as? String) == "user" })?["content"] as? String
        else { return "" }
        return user
    }
}
