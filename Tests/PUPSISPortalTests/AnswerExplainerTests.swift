import XCTest
@testable import PUPSISPortal

/// `AnswerExplainer` itself has no `aiEnabled`/model-empty guard — that lives
/// in the session views that call it (same place `WebNoteEditor.handleAI`
/// guards `LlamaCppClient`), so there's nothing view-free to assert "never
/// called" against here. This suite covers what the function itself owns:
/// the plain-text call and its fallback-to-nil on any failure. Every case
/// pins `ensureServerRunning: { true }` — the real default resolves through
/// `LlamaRuntime`/`ModelCatalog`, which a bare test model id like `"m"`
/// never matches.
@MainActor
final class AnswerExplainerTests: XCTestCase {
    private func card() -> QuizCard {
        QuizCard(front: "Photosynthesis", back: "How plants make food from light", subject: "Bio", citation: "c")
    }

    private func envelope(_ content: String) -> (Data, Int) {
        let wrapper: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        return ((try? JSONSerialization.data(withJSONObject: wrapper)) ?? Data(), 200)
    }

    func testReturnsTheExplanationTextOnSuccess() async {
        let client = LlamaCppClient(send: { _ in self.envelope("Because chlorophyll absorbs light.") })

        let result = await AnswerExplainer.explain(
            card: card(), studentAnswered: "Respiration", model: "m", client: client, ensureServerRunning: { true }
        )

        XCTAssertEqual(result, "Because chlorophyll absorbs light.")
    }

    func testReturnsNilWhenTheClientThrows() async {
        struct Offline: Error {}
        let client = LlamaCppClient(send: { _ in throw Offline() })

        let result = await AnswerExplainer.explain(
            card: card(), studentAnswered: "Respiration", model: "m", client: client, ensureServerRunning: { true }
        )

        XCTAssertNil(result)
    }

    func testReturnsNilOnAnEmptyReply() async {
        let client = LlamaCppClient(send: { _ in self.envelope("   ") })

        let result = await AnswerExplainer.explain(
            card: card(), studentAnswered: "Respiration", model: "m", client: client, ensureServerRunning: { true }
        )

        XCTAssertNil(result)
    }

    func testReturnsNilWhenTheServerCannotBeStarted() async {
        var called = false
        let client = LlamaCppClient(send: { _ in called = true; return self.envelope("explanation") })

        let result = await AnswerExplainer.explain(
            card: card(), studentAnswered: "Respiration", model: "m", client: client, ensureServerRunning: { false }
        )

        XCTAssertNil(result)
        XCTAssertFalse(called, "must not call the model when the server never came up")
    }

    func testBlankStudentAnswerStillProducesARequest() async {
        var captured: Data?
        let client = LlamaCppClient(send: { body in
            captured = body
            return self.envelope("explanation")
        })

        _ = await AnswerExplainer.explain(
            card: card(), studentAnswered: "", model: "m", client: client, ensureServerRunning: { true }
        )

        let json = try? JSONSerialization.jsonObject(with: captured ?? Data()) as? [String: Any]
        let messages = json?["messages"] as? [[String: String]]
        let userContent = messages?.last?["content"]
        XCTAssertTrue(userContent?.contains("nothing / left it blank") ?? false)
    }
}
