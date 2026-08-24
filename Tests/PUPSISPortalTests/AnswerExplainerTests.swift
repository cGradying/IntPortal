import XCTest
@testable import PUPSISPortal

/// `AnswerExplainer` itself has no `aiEnabled`/model-empty guard — that lives
/// in the session views that call it (same place `WebNoteEditor.handleAI`
/// guards `OllamaClient`), so there's nothing view-free to assert "never
/// called" against here. This suite covers what the function itself owns:
/// the plain-text call and its fallback-to-nil on any failure.
@MainActor
final class AnswerExplainerTests: XCTestCase {
    private func card() -> QuizCard {
        QuizCard(front: "Photosynthesis", back: "How plants make food from light", subject: "Bio", citation: "c")
    }

    func testReturnsTheExplanationTextOnSuccess() async {
        let client = OllamaClient(send: { _ in
            let payload = try! JSONSerialization.data(withJSONObject: ["response": "Because chlorophyll absorbs light."])
            return (payload, 200)
        })

        let result = await AnswerExplainer.explain(card: card(), studentAnswered: "Respiration", model: "m", client: client)

        XCTAssertEqual(result, "Because chlorophyll absorbs light.")
    }

    func testReturnsNilWhenTheClientThrows() async {
        struct Offline: Error {}
        let client = OllamaClient(send: { _ in throw Offline() })

        let result = await AnswerExplainer.explain(card: card(), studentAnswered: "Respiration", model: "m", client: client)

        XCTAssertNil(result)
    }

    func testReturnsNilOnAnEmptyReply() async {
        let client = OllamaClient(send: { _ in
            let payload = try! JSONSerialization.data(withJSONObject: ["response": "   "])
            return (payload, 200)
        })

        let result = await AnswerExplainer.explain(card: card(), studentAnswered: "Respiration", model: "m", client: client)

        XCTAssertNil(result)
    }

    func testBlankStudentAnswerStillProducesARequest() async {
        var captured: Data?
        let client = OllamaClient(send: { body in
            captured = body
            let payload = try! JSONSerialization.data(withJSONObject: ["response": "explanation"])
            return (payload, 200)
        })

        _ = await AnswerExplainer.explain(card: card(), studentAnswered: "", model: "m", client: client)

        let json = try? JSONSerialization.jsonObject(with: captured ?? Data()) as? [String: Any]
        let prompt = json?["prompt"] as? String
        XCTAssertTrue(prompt?.contains("nothing / left it blank") ?? false)
    }
}
