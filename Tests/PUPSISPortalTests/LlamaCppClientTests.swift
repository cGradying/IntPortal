import XCTest
@testable import PUPSISPortal

/// Nothing here touches the network — every case goes through the injected
/// sender, so the suite passes whether or not llama-server is running.
final class LlamaCppClientTests: XCTestCase {

    // MARK: requestBody

    func testRequestBodyCarriesSystemAndUserMessages() throws {
        let data = try LlamaCppClient.requestBody(system: "Answer from context.", user: "Notes:\n...\n\nQuestion: what?")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "Answer from context.")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertTrue(messages[1]["content"]?.contains("what?") == true)
    }

    /// No `model` key — llama.cpp's server serves one model per process,
    /// unlike Ollama's multi-model `/api/generate`.
    func testRequestBodyOmitsModel() throws {
        let data = try LlamaCppClient.requestBody(system: "s", user: "u")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["model"])
    }

    func testRequestBodyDefaultsTemperatureToPointTwo() throws {
        let data = try LlamaCppClient.requestBody(system: "s", user: "u")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["temperature"] as? Double, 0.2)
    }

    /// Settings ▸ Misc's answer-temperature slider — has to actually reach
    /// the request.
    func testRequestBodyHonorsACustomTemperature() throws {
        let data = try LlamaCppClient.requestBody(system: "s", user: "u", temperature: 0.9)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["temperature"] as? Double, 0.9)
    }

    // MARK: parse — the OpenAI-compatible shape

    func testParseExtractsMessageContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"The answer is 42."}}]}"#.utf8)
        XCTAssertEqual(try LlamaCppClient.parse(data), "The answer is 42.")
    }

    func testParseTrimsSurroundingWhitespace() throws {
        let data = Data(#"{"choices":[{"message":{"content":"\n\n  text  \n\n"}}]}"#.utf8)
        XCTAssertEqual(try LlamaCppClient.parse(data), "text")
    }

    func testParseRejectsEmptyContent() {
        let data = Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8)
        XCTAssertThrowsError(try LlamaCppClient.parse(data))
    }

    func testParseRejectsNoChoices() {
        XCTAssertThrowsError(try LlamaCppClient.parse(Data(#"{"choices":[]}"#.utf8)))
    }

    func testParseRejectsMalformedJSON() {
        XCTAssertThrowsError(try LlamaCppClient.parse(Data("not json".utf8)))
    }

    // MARK: complete — end to end through the injected transport

    func testCompleteReturnsModelText() async throws {
        let client = LlamaCppClient(send: { _ in
            (Data(#"{"choices":[{"message":{"content":"Grounded answer."}}]}"#.utf8), 200)
        })
        let answer = try await client.complete(system: "s", user: "u")
        XCTAssertEqual(answer, "Grounded answer.")
    }

    struct Boom: Error {}

    func testCompleteReportsOfflineWhenTheSendThrows() async {
        let client = LlamaCppClient(send: { _ in throw Boom() })
        do {
            _ = try await client.complete(system: "s", user: "u")
            XCTFail("expected an error")
        } catch let error as LlamaCppClient.ClientError {
            if case .offline = error {} else { XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testCompleteReportsHTTPStatus() async {
        let client = LlamaCppClient(send: { _ in (Data(), 500) })
        do {
            _ = try await client.complete(system: "s", user: "u")
            XCTFail("expected an error")
        } catch let error as LlamaCppClient.ClientError {
            if case .http(500) = error {} else { XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
