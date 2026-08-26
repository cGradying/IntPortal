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
}

// download() itself isn't unit-tested here — it reports progress via
// URLSessionDownloadDelegate callbacks against a real network stack, which
// this suite deliberately avoids. Covered by the live packaged-app
// verification pass instead.
