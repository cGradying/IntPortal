import XCTest
@testable import PUPSISPortal

final class AIProviderTests: XCTestCase {
    func testLocalNeedsNoAPIKey() {
        XCTAssertFalse(AIProvider.local.needsAPIKey)
        for provider: AIProvider in [.openai, .google, .anthropic] {
            XCTAssertTrue(provider.needsAPIKey)
        }
    }

    func testOpenAICompatibilitySplitsExactlyOpenAIAndGoogle() {
        XCTAssertTrue(AIProvider.openai.isOpenAICompatible)
        XCTAssertTrue(AIProvider.google.isOpenAICompatible)
        XCTAssertFalse(AIProvider.local.isOpenAICompatible)
        XCTAssertFalse(AIProvider.anthropic.isOpenAICompatible)
    }

    func testLocalHasNoChatEndpoint() {
        // LlamaCppClient.endpoint (hardcoded localhost) is the real one —
        // .local deliberately has no URL here, so nothing can accidentally
        // route a "local" request through this type's endpoint instead.
        XCTAssertNil(AIProvider.local.chatEndpoint)
    }

    func testEveryCloudProviderHasAnEndpointAndADefaultModel() {
        for provider: AIProvider in [.openai, .google, .anthropic] {
            XCTAssertNotNil(provider.chatEndpoint)
            XCTAssertFalse(provider.defaultModel.isEmpty)
        }
    }

    func testLocalDefaultModelIsEmpty() {
        // llama-server serves exactly one model per process — a model id
        // here would be dead weight, same reasoning as LlamaCppClient's own
        // model: parameter being accepted-and-ignored for local requests.
        XCTAssertTrue(AIProvider.local.defaultModel.isEmpty)
    }
}
