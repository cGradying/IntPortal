import Foundation

/// Where the launch sequence is: the void, the frame assembling, the swirl
/// igniting, then resting on sign-in or the hub, and finally the warp in.
enum LandingPhase: Equatable {
    case void
    case forming(Double)
    case ignite(Double)
    case signIn
    case hub
    case warp(Double)
    case done

    /// Share of the frame's 24 blocks in place.
    var formed: Double {
        switch self {
        case .void: 0
        case .forming(let p): p
        default: 1
        }
    }

    /// How lit the swirl is.
    var lit: Double {
        switch self {
        case .void, .forming: 0
        case .ignite(let p): p
        default: 1
        }
    }

    var isRest: Bool { self == .signIn || self == .hub }

    var isWarp: Bool {
        if case .warp = self { true } else { false }
    }

    private var warpProgress: Double {
        if case .warp(let p) = self { p } else if self == .done { 1 } else { 0 }
    }

    /// Camera dolly into the portal: 1 to 12, slow start, hard finish.
    var zoom: Double { 1 + pow(warpProgress, 2.6) * 11 }
    var swirlSpeed: Double { 1 + warpProgress * 8 }
    /// Pixel size of the swirl and the whole scene during the warp.
    var pixelCell: Double { 3 + warpProgress * 9 }
    /// The gold-white flash lands at 82% of the warp.
    var flash: Double { warpProgress >= LandingSequence.flashAt ? 1 : 0 }
}

/// Timing for the launch sequence (spec 09). Pure, so every beat is testable
/// and a snapshot can pin any phase.
struct LandingSequence {
    var signedIn: Bool
    var reduceMotion: Bool
    /// Settings › General › Play portal intro. Off lands on the rest phase
    /// with the frame already built.
    var playIntro = true

    static let formStart = 0.4
    static let formEnd = 1.6
    static let igniteStart = 1.7
    static let igniteEnd = 2.2
    static let warpLength = 0.95
    static let flashAt = 0.82
    static let warpDone = 1.08
    static let reducedWarpDone = 0.22
    /// How far a skip jumps the clock: past every intro beat.
    static let skip = 5.0

    /// `elapsed` since the landing appeared; `warpStartedAt` on that same clock.
    func phase(elapsed: TimeInterval, warpStartedAt: TimeInterval?) -> LandingPhase {
        if let warpStartedAt {
            let e = elapsed - warpStartedAt
            if e >= (reduceMotion ? Self.reducedWarpDone : Self.warpDone) { return .done }
            return reduceMotion ? .warp(0) : .warp(min(max(e / Self.warpLength, 0), 1))
        }
        let rest: LandingPhase = signedIn ? .hub : .signIn
        guard playIntro, !reduceMotion else { return rest }
        switch elapsed {
        case ..<Self.formStart: return .void
        case ..<Self.formEnd: return .forming((elapsed - Self.formStart) / (Self.formEnd - Self.formStart))
        case ..<Self.igniteStart: return .forming(1)
        case ..<Self.igniteEnd: return .ignite((elapsed - Self.igniteStart) / (Self.igniteEnd - Self.igniteStart))
        default: return rest
        }
    }
}
