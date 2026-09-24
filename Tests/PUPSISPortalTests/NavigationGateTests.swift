import XCTest
@testable import PUPSISPortal

/// `NavigationGate` is the single-flight chokepoint every web-view wait in
/// `PortalController` routes through (sign-in, schedule/grades load, the
/// grade-history term picker). These tests drive it with a fake navigation
/// driver — a closure that calls `resume()`/`fail(_:)` directly, standing in
/// for a real `WKNavigationDelegate` callback — so the single-flight and
/// sign-out-cancellation behaviour is verified without a real `WKWebView`.
@MainActor
final class NavigationGateTests: XCTestCase {
    /// Runs `gate.wait` on a background `Task` and captures whether it threw,
    /// since `wait` itself can't be awaited directly from a second concurrent
    /// caller in the same test.
    private func spawnWait(
        _ gate: NavigationGate,
        timeout: TimeInterval = 5,
        _ action: @escaping () -> Void = {}
    ) -> Task<Result<Void, Error>, Never> {
        Task {
            do {
                try await gate.wait(timeout: timeout, action)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    func testResumeCompletesTheWaitingCaller() async throws {
        let gate = NavigationGate()
        // The fake driver "navigates" and reports success asynchronously,
        // like a real `didFinish` delegate callback would.
        try await gate.wait(timeout: 5) {
            Task { @MainActor in gate.resume() }
        }
        // No throw: reaching here is the assertion.
    }

    /// The bug: a second load arriving while the first is still outstanding
    /// (e.g. a menu-bar/Grades-tab refresh firing mid sign-in) used to
    /// silently overwrite the pending continuation, orphaning the first
    /// caller forever — sign-in hung with `status` stuck `.loggingIn`. The
    /// fix fails the older waiter instead, so it throws rather than hangs.
    func testSecondWaitFailsTheFirstInsteadOfHanging() async throws {
        let gate = NavigationGate()

        // First "load" arms its wait but nothing ever completes it on its
        // own — modeling a slow navigation that's still in flight.
        let first = spawnWait(gate)

        // Give the first wait a beat to actually install its continuation
        // before the second arrives, so this test is about arrival order,
        // not a timing race.
        try await Task.sleep(nanoseconds: 20_000_000)

        // A second caller arrives and completes immediately.
        try await gate.wait(timeout: 5) { Task { @MainActor in gate.resume() } }

        guard case .failure(let error) = await first.value else {
            XCTFail("the superseded wait should throw, not hang or succeed")
            return
        }
        XCTAssertEqual(error as? PortalError, .superseded)
    }

    /// Sign-out: `cancelAll()` must fail whatever navigation wait is
    /// outstanding right now (rather than leaving it to run for up to the
    /// full timeout), and must invalidate the generation so a flow that
    /// captured it earlier knows its result is stale. This is the guard
    /// `loadSchedule`/`loadGrades` use to skip re-saving a cache after
    /// `signOut()` already deleted it — "slow load + sign-out → no cache
    /// file" at the mechanism level.
    func testCancelAllFailsThePendingWaitAndInvalidatesGeneration() async throws {
        let gate = NavigationGate()
        let capturedGeneration = gate.generation

        let pending = spawnWait(gate) // never resumed by the driver itself

        try await Task.sleep(nanoseconds: 20_000_000)
        gate.cancelAll()

        guard case .failure(let error) = await pending.value else {
            XCTFail("a cancelled wait should throw, not hang or succeed")
            return
        }
        XCTAssertTrue(error is CancellationError)
        XCTAssertFalse(
            gate.isCurrent(capturedGeneration),
            "a flow that started before sign-out must see itself as stale afterward"
        )
    }

    /// The gate must stay usable after a supersede/cancel — later, unrelated
    /// work isn't permanently wedged by an earlier conflict.
    func testGateIsReusableAfterASupersede() async throws {
        let gate = NavigationGate()
        _ = spawnWait(gate) // left pending, will be superseded below

        try await Task.sleep(nanoseconds: 20_000_000)
        try await gate.wait(timeout: 5) { Task { @MainActor in gate.resume() } }
        // A third, independent wait after that still completes normally.
        try await gate.wait(timeout: 5) { Task { @MainActor in gate.resume() } }
    }
}
