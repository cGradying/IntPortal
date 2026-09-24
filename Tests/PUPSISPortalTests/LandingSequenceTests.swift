import SwiftUI
import XCTest
@testable import PUPSISPortal

final class LandingSequenceTests: XCTestCase {
    private let signedIn = LandingSequence(signedIn: true, reduceMotion: false)
    private let signedOut = LandingSequence(signedIn: false, reduceMotion: false)

    func testIntroBeatsInOrder() {
        XCTAssertEqual(signedIn.phase(elapsed: 0.2, warpStartedAt: nil), .void)
        guard case .forming(let formed) = signedIn.phase(elapsed: 1.0, warpStartedAt: nil) else { return XCTFail("not forming") }
        XCTAssertEqual(formed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(signedIn.phase(elapsed: 1.65, warpStartedAt: nil), .forming(1))
        guard case .ignite(let lit) = signedIn.phase(elapsed: 1.95, warpStartedAt: nil) else { return XCTFail("not igniting") }
        XCTAssertEqual(lit, 0.5, accuracy: 1e-9)
        XCTAssertEqual(signedIn.phase(elapsed: 2.5, warpStartedAt: nil), .hub)
        XCTAssertEqual(signedOut.phase(elapsed: 2.5, warpStartedAt: nil), .signIn)
    }

    func testSkipJumpsPastTheIntro() {
        XCTAssertEqual(signedIn.phase(elapsed: 0.1 + LandingSequence.skip, warpStartedAt: nil), .hub)
    }

    func testWarpFlashesAtEightyTwoPercentAndEnds() {
        let before = signedIn.phase(elapsed: 3 + 0.95 * 0.8, warpStartedAt: 3)
        let after = signedIn.phase(elapsed: 3 + 0.95 * 0.84, warpStartedAt: 3)
        XCTAssertEqual(before.flash, 0)
        XCTAssertEqual(after.flash, 1)
        XCTAssertEqual(signedIn.phase(elapsed: 3 + 1.08, warpStartedAt: 3), .done)
        XCTAssertEqual(signedIn.phase(elapsed: 3 + 1.0, warpStartedAt: 3), .warp(1))
        XCTAssertEqual(LandingPhase.warp(1).zoom, 12, accuracy: 1e-9)
        XCTAssertEqual(LandingPhase.warp(1).pixelCell, 12, accuracy: 1e-9)
    }

    func testReduceMotionSkipsTheIntroAndShortensTheWarp() {
        let reduced = LandingSequence(signedIn: true, reduceMotion: true)
        XCTAssertEqual(reduced.phase(elapsed: 0, warpStartedAt: nil), .hub)
        XCTAssertEqual(reduced.phase(elapsed: 0.1, warpStartedAt: 0), .warp(0))
        XCTAssertEqual(reduced.phase(elapsed: 0.22, warpStartedAt: 0), .done)
        XCTAssertEqual(LandingPhase.warp(0).zoom, 1)
    }

    func testIntroOffLandsBuilt() {
        let noIntro = LandingSequence(signedIn: false, reduceMotion: false, playIntro: false)
        XCTAssertEqual(noIntro.phase(elapsed: 0, warpStartedAt: nil), .signIn)
        XCTAssertEqual(LandingPhase.signIn.formed, 1)
        XCTAssertEqual(LandingPhase.signIn.lit, 1)
    }
}

@MainActor
final class LandingSnapshotTests: XCTestCase {
    private func stage(_ phase: LandingPhase, ring: Int = 0, hint: String? = nil, failure: String? = nil) -> some View {
        LandingStage(
            phase: phase, time: 12, ring: .constant(ring), hint: hint,
            liveSubtitle: "via sis8", signedInAs: "2026-00000-MN-0", existing: nil, failure: failure,
            onSave: { _ in true }, onSelect: { _ in }, onSwitchAccount: {}, onSettings: {}
        )
        .frame(width: 1280, height: 800)
    }

    func testEveryBeatRenders() throws {
        Shaders.library = Shaders.load(from: .module)
        defer { Shaders.library = nil }
        for (name, view) in [
            ("landing-forming", AnyView(stage(.forming(0.6)))),
            ("landing-hub", AnyView(stage(.hub))),
            ("landing-hub-locked", AnyView(stage(.hub, ring: 1, hint: "That portal is not connected yet. Only PUP SIS is live."))),
            ("landing-signin", AnyView(stage(.signIn, failure: "Sign-in didn't go through — check your student number, birthdate, and password."))),
            ("landing-warp", AnyView(stage(.warp(0.5)))),
            ("landing-flash", AnyView(stage(.warp(0.9)))),
        ] {
            let image = try Snapshot.render(view, name: name, palette: .registrarNight, scheme: .dark)
            XCTAssertEqual(image.size, CGSize(width: 1280, height: 800), name)
        }
    }

    func testStudentNumberFormat() {
        XCTAssertTrue(SignInPanel.isStudentNumber("2026-00000-MN-0"))
        XCTAssertTrue(SignInPanel.isStudentNumber(" 2011-12345-tg-12 "))
        XCTAssertFalse(SignInPanel.isStudentNumber("2026-00000-MN"))
        XCTAssertFalse(SignInPanel.isStudentNumber("202600000MN0"))
    }
}
