import XCTest
@testable import PUPSISPortal

/// Nothing here touches the network — every case goes through the injected
/// sender, so the suite passes whether or not `llama-server` is running.
final class LlamaCppClientTests: XCTestCase {

    // MARK: requestBody — plain completion (generate)

    func testRequestBodyCarriesSystemAndUserMessages() throws {
        let data = try LlamaCppClient.requestBody(selection: "Notes:\n...\n\nQuestion: what?", instruction: "Answer from context.")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "Answer from context.")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertTrue(messages[1]["content"]?.contains("what?") == true)
    }

    /// No `model` key — llama.cpp's server serves one model per process.
    func testRequestBodyOmitsModel() throws {
        let data = try LlamaCppClient.requestBody(selection: "u", instruction: "s")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["model"])
    }

    // MARK: truncatedForContext — the note editor's "Ask AI" pill

    func testTruncatedForContextLeavesAShortSelectionUntouched() {
        let selection = "Just a short highlighted sentence."
        let result = LlamaCppClient.truncatedForContext(selection, instruction: "Summarize.", contextSize: 4096)
        XCTAssertEqual(result, selection)
    }

    /// Regression: the note editor's "Ask AI" pill sent the selected text
    /// completely unbounded, which could exceed the configured context size
    /// with a long note — llama-server's response to that overflow is an
    /// *empty* completion (ClientError.empty), not a clear error.
    func testTruncatedForContextShortensAVeryLongSelectionAtASmallContextSize() {
        let longSelection = String(repeating: "lecture notes ", count: 2000) // ~28,000 chars
        let result = LlamaCppClient.truncatedForContext(longSelection, instruction: "Structure this.", contextSize: 3072)
        XCTAssertLessThan(result.count, longSelection.count)
        XCTAssertTrue(result.hasSuffix("[...truncated to fit the configured context size]"))
    }

    func testTruncatedForContextNeverGoesBelowTheFloorEvenAtATinyContextSize() {
        let longSelection = String(repeating: "x", count: 10000)
        let result = LlamaCppClient.truncatedForContext(longSelection, instruction: "s", contextSize: 0)
        // Floored at 200 tokens * 4 chars/token = 800, plus the suffix.
        XCTAssertLessThanOrEqual(result.count, 800 + "\n[...truncated to fit the configured context size]".count)
    }

    func testTruncatedForContextAtHighContextLeavesAModeratelyLongNoteUntouched() {
        let selection = String(repeating: "a page of real notes. ", count: 100) // ~2,300 chars
        let result = LlamaCppClient.truncatedForContext(selection, instruction: "Summarize.", contextSize: 32768)
        XCTAssertEqual(result, selection)
    }

    // MARK: parseContent — the OpenAI-compatible plain-text shape

    func testParseContentExtractsMessageContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"The answer is 42."}}]}"#.utf8)
        XCTAssertEqual(try LlamaCppClient.parseContent(data), "The answer is 42.")
    }

    func testParseContentTrimsSurroundingWhitespace() throws {
        let data = Data(#"{"choices":[{"message":{"content":"\n\n  text  \n\n"}}]}"#.utf8)
        XCTAssertEqual(try LlamaCppClient.parseContent(data), "text")
    }

    func testParseContentRejectsEmptyContent() {
        let data = Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8)
        XCTAssertThrowsError(try LlamaCppClient.parseContent(data))
    }

    func testParseContentRejectsNoChoices() {
        XCTAssertThrowsError(try LlamaCppClient.parseContent(Data(#"{"choices":[]}"#.utf8)))
    }

    func testParseContentRejectsMalformedJSON() {
        XCTAssertThrowsError(try LlamaCppClient.parseContent(Data("not json".utf8)))
    }

    // MARK: generate — end to end through the injected transport

    func testGenerateReturnsModelText() async throws {
        let client = LlamaCppClient(send: { _ in
            (Data(#"{"choices":[{"message":{"content":"Grounded answer."}}]}"#.utf8), 200)
        })
        let answer = try await client.generate(selection: "u", instruction: "s")
        XCTAssertEqual(answer, "Grounded answer.")
    }

    struct Boom: Error {}

    func testGenerateReportsOfflineWhenTheSendThrows() async {
        let client = LlamaCppClient(send: { _ in throw Boom() })
        do {
            _ = try await client.generate(selection: "u", instruction: "s")
            XCTFail("expected an error")
        } catch let error as LlamaCppClient.ClientError {
            if case .offline = error {} else { XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testGenerateReportsHTTPStatus() async {
        let client = LlamaCppClient(send: { _ in (Data(), 500) })
        do {
            _ = try await client.generate(selection: "u", instruction: "s")
            XCTFail("expected an error")
        } catch let error as LlamaCppClient.ClientError {
            if case .http(500) = error {} else { XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    // MARK: chatRequestBody — schema-constrained chat, thinking

    func testChatRequestBodyCarriesResponseFormatSchema() throws {
        let schema: [String: Any] = ["type": "object", "properties": ["reply": ["type": "string"]]]
        let data = try LlamaCppClient.chatRequestBody(
            messages: [.init(role: .user, content: "hi")], schema: schema
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let format = try XCTUnwrap(json["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let wrapped = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertNotNil(wrapped["schema"])
    }

    /// Confirmed live against a real `llama-server`: `reasoning_effort` is
    /// the request field that actually gates thinking (`"none"` genuinely
    /// disables it) — see the type's own doc comment.
    func testChatRequestBodySendsReasoningEffort() throws {
        let data = try LlamaCppClient.chatRequestBody(
            messages: [.init(role: .user, content: "hi")], schema: ["type": "object"], think: .max
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
    }

    func testChatRequestBodyDefaultsReasoningEffortToNoneWhenOff() throws {
        let data = try LlamaCppClient.chatRequestBody(
            messages: [.init(role: .user, content: "hi")], schema: ["type": "object"], think: .off
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["reasoning_effort"] as? String, "none")
    }

    func testChatRequestBodyHonorsACustomTemperature() throws {
        let data = try LlamaCppClient.chatRequestBody(
            messages: [.init(role: .user, content: "hi")], schema: ["type": "object"], temperature: 0.9
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["temperature"] as? Double, 0.9)
    }

    /// Reasoning comes back in its own `message.reasoning_content` field,
    /// never mixed into `content` — confirmed live, so no `<think>`-tag
    /// stripping is needed anywhere downstream.
    func testParseChatContentSeparatesThinkingFromContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"{\"reply\":\"4\"}","reasoning_content":"2+2 is 4"}}]}"#.utf8)
        let (content, thinking) = try LlamaCppClient.parseChatContent(data)
        XCTAssertEqual(content, #"{"reply":"4"}"#)
        XCTAssertEqual(thinking, "2+2 is 4")
    }

    func testParseChatContentThinkingIsEmptyWhenAbsent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"{\"reply\":\"4\"}"}}]}"#.utf8)
        let (_, thinking) = try LlamaCppClient.parseChatContent(data)
        XCTAssertEqual(thinking, "")
    }

    func testChatReturnsContentAndThinking() async throws {
        let client = LlamaCppClient(send: { _ in
            (Data(#"{"choices":[{"message":{"content":"{\"reply\":\"ok\"}","reasoning_content":"thinking..."}}]}"#.utf8), 200)
        })
        let result = try await client.chat(messages: [.init(role: .user, content: "hi")], schema: ["type": "object"])
        XCTAssertEqual(result.content, #"{"reply":"ok"}"#)
        XCTAssertEqual(result.thinking, "thinking...")
    }

    // MARK: embeddings — the .embed-role server

    func testEmbedRequestBodyOmitsModel() throws {
        let data = try LlamaCppClient.embedRequestBody(texts: ["a", "b"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["model"])
        XCTAssertEqual(json["input"] as? [String], ["a", "b"])
    }

    func testParseEmbeddingsExtractsVectorsInOrder() throws {
        let data = Data(#"{"data":[{"embedding":[0.1,0.2]},{"embedding":[0.3,0.4]}]}"#.utf8)
        let vectors = try LlamaCppClient.parseEmbeddings(data)
        XCTAssertEqual(vectors, [[0.1, 0.2], [0.3, 0.4]])
    }

    func testParseEmbeddingsRejectsEmptyData() {
        XCTAssertThrowsError(try LlamaCppClient.parseEmbeddings(Data(#"{"data":[]}"#.utf8)))
    }

    func testEmbedReturnsEmptyForEmptyInputWithoutCallingSend() async throws {
        var called = false
        let client = LlamaCppClient(sendEmbed: { _ in called = true; return (Data(), 200) })
        let result = try await client.embed(texts: [])
        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(called)
    }

    func testEmbedUsesTheEmbedTransportNotTheChatOne() async throws {
        var chatCalled = false
        var embedCalled = false
        let client = LlamaCppClient(
            send: { _ in chatCalled = true; return (Data(), 200) },
            sendEmbed: { _ in
                embedCalled = true
                return (Data(#"{"data":[{"embedding":[1.0]}]}"#.utf8), 200)
            }
        )
        _ = try await client.embed(texts: ["hello"])
        XCTAssertTrue(embedCalled)
        XCTAssertFalse(chatCalled)
    }

    // MARK: injectingModel — the cloud-provider request-body patch (ticket #17)

    func testInjectingModelAddsTheModelField() throws {
        let body = try LlamaCppClient.requestBody(selection: "u", instruction: "s")
        let patched = LlamaCppClient.injectingModel("gpt-4o-mini", into: body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: patched) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        // The local builders are untouched — this only ever runs on the
        // outgoing cloud request, never mutates what local requests send.
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])["model"])
    }

    /// llama.cpp/vLLM-specific — several cloud providers 400 on an
    /// unrecognized top-level field rather than ignoring it.
    func testInjectingModelStripsReasoningEffort() throws {
        let body = try LlamaCppClient.chatRequestBody(
            messages: [.init(role: .user, content: "hi")], schema: ["type": "object"], think: .low
        )
        XCTAssertNotNil(try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])["reasoning_effort"])

        let patched = LlamaCppClient.injectingModel("gpt-4o-mini", into: body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: patched) as? [String: Any])
        XCTAssertNil(json["reasoning_effort"])
    }

    // MARK: Anthropic translation (ticket #17) — reenvelopingAsOpenAI

    func testReenvelopingAsOpenAIExtractsPlainTextReply() throws {
        let anthropicData = Data(#"{"content":[{"type":"text","text":"The answer is 42."}]}"#.utf8)
        let openAIShaped = LlamaCppClient.reenvelopingAsOpenAI(anthropicData, forcedToolName: nil)
        XCTAssertEqual(try LlamaCppClient.parseContent(openAIShaped), "The answer is 42.")
    }

    /// A schema-locked turn forces a tool call — the reply arrives as
    /// content[0].input, already a structured object, not a string; it must
    /// be re-serialized to a JSON *string* to land in the same "content"
    /// field a plain-text reply would, since that's what parseChatContent
    /// (and AssistantReply.decode downstream of it) expect to parse.
    func testReenvelopingAsOpenAIExtractsForcedToolInputAsJSONString() throws {
        let anthropicData = Data(#"""
        {"content":[{"type":"tool_use","name":"reply","input":{"reply":"hi","actions":[]}}]}
        """#.utf8)
        let openAIShaped = LlamaCppClient.reenvelopingAsOpenAI(anthropicData, forcedToolName: "reply")
        let (content, thinking) = try LlamaCppClient.parseChatContent(openAIShaped)
        XCTAssertEqual(thinking, "")
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        XCTAssertEqual(decoded["reply"] as? String, "hi")
    }

    func testReenvelopingAsOpenAIPassesThroughUnrecognizedShapeUnchanged() {
        let malformed = Data(#"{"not":"anthropic-shaped"}"#.utf8)
        XCTAssertEqual(LlamaCppClient.reenvelopingAsOpenAI(malformed, forcedToolName: nil), malformed)
    }
}

// download() itself isn't unit-tested here — it reports progress via
// URLSessionDownloadDelegate callbacks against a real network stack, which
// this suite deliberately avoids. Covered by the live packaged-app
// verification pass instead.
