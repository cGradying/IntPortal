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
        let client = OllamaClient { _ in (Data(#"{"response":"drafted"}"#.utf8), 200) }
        let text = try await client.generate(model: "m", selection: "seed")
        XCTAssertEqual(text, "drafted")
    }

    func testGenerateSendsTheBuiltBody() async throws {
        actor Captured { var body: Data?; func set(_ d: Data) { body = d } }
        let captured = Captured()
        let client = OllamaClient { body in
            await captured.set(body)
            return (Data(#"{"response":"ok"}"#.utf8), 200)
        }
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
        let client = OllamaClient { _ in throw Boom() }
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
        let client = OllamaClient { _ in (Data(), 404) }
        do {
            _ = try await client.generate(model: "typo", selection: "seed")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"),
                          "got: \(error.localizedDescription)")
        }
    }

    func testGenerateRejectsEmptyModelOutput() async {
        let client = OllamaClient { _ in (Data(#"{"response":""}"#.utf8), 200) }
        do {
            _ = try await client.generate(model: "m", selection: "seed")
            XCTFail("expected an error")
        } catch {
            // Any error will do; the point is it doesn't silently insert nothing.
        }
    }
}
