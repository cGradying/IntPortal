import XCTest
@testable import PUPSISPortal

/// Nothing here touches the network — every case goes through the injected
/// sender, so the suite passes whether or not Ollama is installed.
final class OllamaClientTests: XCTestCase {

    // MARK: requestBody

    func testRequestBodyCarriesModelAndPrompt() throws {
        let data = try OllamaClient.requestBody(model: "llama3.2", selection: "photosynthesis")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "llama3.2")
        // Non-streaming: the client inserts once, when the whole answer is in.
        XCTAssertEqual(json["stream"] as? Bool, false)

        let prompt = try XCTUnwrap(json["prompt"] as? String)
        XCTAssertTrue(prompt.contains("photosynthesis"), "the selection must reach the model")
        XCTAssertTrue(prompt.contains(OllamaClient.instruction), "the house style must be applied")
    }

    func testRequestBodyEscapesAwkwardSelections() throws {
        let nasty = "quotes \" backslash \\ newline \n emoji 🌱"
        let data = try OllamaClient.requestBody(model: "m", selection: nasty)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(json["prompt"] as? String).contains(nasty))
    }

    // MARK: parse

    func testParseExtractsResponse() throws {
        let data = Data(#"{"response":"Plants convert light.","done":true}"#.utf8)
        XCTAssertEqual(try OllamaClient.parse(data), "Plants convert light.")
    }

    func testParseTrimsSurroundingWhitespace() throws {
        let data = Data(#"{"response":"\n\n  text  \n\n"}"#.utf8)
        XCTAssertEqual(try OllamaClient.parse(data), "text")
    }

    func testParseRejectsEmptyResponse() {
        let data = Data(#"{"response":"   "}"#.utf8)
        XCTAssertThrowsError(try OllamaClient.parse(data))
    }

    func testParseRejectsMalformedJSON() {
        XCTAssertThrowsError(try OllamaClient.parse(Data("not json".utf8)))
    }

    func testParseRejectsMissingField() {
        XCTAssertThrowsError(try OllamaClient.parse(Data(#"{"done":true}"#.utf8)))
    }

    // MARK: parseModels

    /// Shape confirmed against a real `GET /api/tags` on a machine with Ollama
    /// running — the payload carries a lot more per model than the name.
    func testParseModelsTakesNamesAndSorts() {
        let data = Data("""
        {"models":[
          {"name":"qwen2.5-coder:3b","size":1,"details":{"family":"qwen2"}},
          {"name":"llama3.2","size":2,"details":{"family":"llama"}}
        ]}
        """.utf8)
        XCTAssertEqual(OllamaClient.parseModels(data), ["llama3.2", "qwen2.5-coder:3b"])
    }

    func testParseModelsHandlesNoModelsPulled() {
        XCTAssertEqual(OllamaClient.parseModels(Data(#"{"models":[]}"#.utf8)), [])
    }

    /// Ollama not running: the fetch fails and we get nothing decodable. Empty,
    /// never a crash — Settings shows "is Ollama running?" off the back of this.
    func testParseModelsHandlesGarbage() {
        XCTAssertEqual(OllamaClient.parseModels(Data("connection refused".utf8)), [])
    }

    // MARK: generate

    func testGenerateReturnsModelText() async throws {
        let client = OllamaClient(send: { _ in (Data(#"{"response":"drafted"}"#.utf8), 200) })
        let text = try await client.generate(model: "m", selection: "seed")
        XCTAssertEqual(text, "drafted")
    }

    func testGenerateSendsTheBuiltBody() async throws {
        actor Captured { var body: Data?; func set(_ d: Data) { body = d } }
        let captured = Captured()
        let client = OllamaClient(send: { body in
            await captured.set(body)
            return (Data(#"{"response":"ok"}"#.utf8), 200)
        })
        _ = try await client.generate(model: "mistral", selection: "seed text")

        let sent = await captured.body
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(sent)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "mistral")
        XCTAssertTrue(try XCTUnwrap(json["prompt"] as? String).contains("seed text"))
    }

    /// Ollama not running is the common case, and the message has to say so —
    /// this is the failure a first-time user will actually hit.
    func testGenerateReportsOfflineWhenTheSendThrows() async {
        struct Boom: Error {}
        let client = OllamaClient(send: { _ in throw Boom() })
        do {
            _ = try await client.generate(model: "m", selection: "seed")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Ollama"),
                          "got: \(error.localizedDescription)")
        }
    }

    /// A wrong model name is a 404 from Ollama, not a transport failure.
    func testGenerateReportsHTTPStatus() async {
        let client = OllamaClient(send: { _ in (Data(), 404) })
        do {
            _ = try await client.generate(model: "typo", selection: "seed")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"),
                          "got: \(error.localizedDescription)")
        }
    }

    func testGenerateRejectsEmptyModelOutput() async {
        let client = OllamaClient(send: { _ in (Data(#"{"response":""}"#.utf8), 200) })
        do {
            _ = try await client.generate(model: "m", selection: "seed")
            XCTFail("expected an error")
        } catch {
            // Any error will do; the point is it doesn't silently insert nothing.
        }
    }

    // MARK: parseRunningModels

    /// Shape confirmed against a real `GET /api/ps` on a machine with a model
    /// loaded — distinct payload from `/api/tags` (adds expires_at, VRAM size).
    func testParseRunningModelsTakesNames() {
        let data = Data("""
        {"models":[
          {"name":"qwen3.5:4b","model":"qwen3.5:4b","size":1,"expires_at":"2026-08-15T10:07:35+08:00"}
        ]}
        """.utf8)
        XCTAssertEqual(OllamaClient.parseRunningModels(data), ["qwen3.5:4b"])
    }

    func testParseRunningModelsHandlesNothingLoaded() {
        XCTAssertEqual(OllamaClient.parseRunningModels(Data(#"{"models":[]}"#.utf8)), [])
    }

    func testParseRunningModelsHandlesGarbage() {
        XCTAssertEqual(OllamaClient.parseRunningModels(Data("connection refused".utf8)), [])
    }

    // MARK: unload

    func testUnloadRequestBodySetsKeepAliveToZero() throws {
        let data = try OllamaClient.unloadRequestBody(model: "qwen3.5:4b")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen3.5:4b")
        // Zero, not omitted — that's what actually tells Ollama to drop it
        // now rather than just not extending how long it stays resident.
        XCTAssertEqual(json["keep_alive"] as? Int, 0)
    }

    func testUnloadSendsTheUnloadRequestBody() async throws {
        actor Captured { var body: Data?; func set(_ d: Data) { body = d } }
        let captured = Captured()
        let client = OllamaClient(send: { body in
            await captured.set(body)
            return (Data(), 200)
        })
        await client.unload(model: "qwen2.5-coder:3b")

        let capturedBody = await captured.body
        let sent = try XCTUnwrap(capturedBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen2.5-coder:3b")
    }

    /// Unloading is best-effort cleanup, not a user-waited-on action — a
    /// failure here must never throw or surface an error line.
    func testUnloadSwallowsTransportFailure() async {
        struct Boom: Error {}
        let client = OllamaClient(send: { _ in throw Boom() })
        await client.unload(model: "m") // must not throw
    }
}
