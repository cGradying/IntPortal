import XCTest
@testable import PUPSISPortal

/// Minor fix: `MLXBackend.ensureLoaded` used to be able to start two
/// concurrent multi-hundred-MB model loads for the same directory if two
/// callers raced it. `SingleFlight` is the generic, MLX-agnostic fix —
/// tested here with a plain counting closure so it never needs a real
/// `ModelContainer` (which needs real MLX weights to construct at all).
final class SingleFlightTests: XCTestCase {
    func testConcurrentCallsForTheSameKeyRunTheOperationOnce() async throws {
        let singleFlight = SingleFlight<String, Int>()
        let callCount = Counter()

        async let first = singleFlight.run("model-a") {
            await callCount.increment()
            try await Task.sleep(for: .milliseconds(100))
            return 1
        }
        async let second = singleFlight.run("model-a") {
            await callCount.increment()
            try await Task.sleep(for: .milliseconds(100))
            return 2
        }

        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b, "both callers must observe the same in-flight result")
        let count = await callCount.value
        XCTAssertEqual(count, 1, "the operation must run exactly once for two overlapping calls with the same key")
    }

    func testDifferentKeysRunIndependently() async throws {
        let singleFlight = SingleFlight<String, Int>()
        let callCount = Counter()

        async let a = singleFlight.run("model-a") { await callCount.increment(); return 1 }
        async let b = singleFlight.run("model-b") { await callCount.increment(); return 2 }
        _ = try await (a, b)

        let count = await callCount.value
        XCTAssertEqual(count, 2, "different keys must not be coalesced together")
    }

    func testASecondCallAfterTheFirstCompletesRunsAgain() async throws {
        let singleFlight = SingleFlight<String, Int>()
        let callCount = Counter()

        _ = try await singleFlight.run("model-a") { await callCount.increment(); return 1 }
        _ = try await singleFlight.run("model-a") { await callCount.increment(); return 1 }

        let count = await callCount.value
        XCTAssertEqual(count, 2, "single-flight only coalesces genuinely overlapping calls, not sequential ones")
    }

    func testThrowingOperationPropagatesToEveryWaiter() async {
        struct Failure: Error {}
        let singleFlight = SingleFlight<String, Int>()

        async let first: Void = {
            do {
                _ = try await singleFlight.run("model-a") {
                    try await Task.sleep(for: .milliseconds(50))
                    throw Failure()
                }
                XCTFail("expected Failure")
            } catch is Failure {
            } catch {
                XCTFail("expected Failure, got \(error)")
            }
        }()
        async let second: Void = {
            do {
                _ = try await singleFlight.run("model-a") { 0 }
                XCTFail("expected Failure")
            } catch is Failure {
            } catch {
                XCTFail("expected Failure, got \(error)")
            }
        }()
        _ = await (first, second)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
