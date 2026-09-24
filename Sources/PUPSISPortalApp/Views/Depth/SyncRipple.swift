import SwiftUI

/// One pixel shockwave out from `origin` each time `trigger` changes: green
/// and all the way to the window edge on a good sync, a short red stutter on
/// a failure. Nothing plays under Reduce Motion; the sync line says it.
struct SyncRipple: ViewModifier {
    let trigger: Int
    let ok: Bool
    let origin: CGPoint
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    /// Ring radius as a share of the farthest window corner, over time.
    static func reach(_ t: Double, ok: Bool) -> Double {
        if ok { return t }
        switch t {
        case ..<0.4: return t / 0.4 * 0.28
        case ..<0.55: return 0.28 - (t - 0.4) / 0.15 * 0.08
        case ..<0.7: return 0.2 + (t - 0.55) / 0.15 * 0.07
        default: return 0.27 - (t - 0.7) / 0.3 * 0.05
        }
    }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let far = [CGPoint.zero, CGPoint(x: geo.size.width, y: 0), CGPoint(x: 0, y: geo.size.height), CGPoint(x: geo.size.width, y: geo.size.height)]
                .map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? 0
            content
                .keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, t in
                    let r = Self.reach(t, ok: ok) * far
                    let live = t < 1 && !reduceMotion
                    view
                        .layerEffect(
                            (Shaders.library ?? ShaderLibrary.default).syncRipple(
                                .float2(origin), .float(r), .float(18), .float(live ? 8 * (1 - t) : 0)
                            ),
                            maxSampleOffset: CGSize(width: 8, height: 8),
                            isEnabled: live && Shaders.library != nil
                        )
                        .overlay {
                            Circle()
                                .stroke(ok ? palette.roles.good : palette.roles.bad, lineWidth: 4)
                                .frame(width: 2 * r, height: 2 * r)
                                .position(origin)
                                .opacity(live ? 0.9 * (1 - t) + 0.1 : 0)
                                .allowsHitTesting(false)
                        }
                } keyframes: { _ in
                    LinearKeyframe(0.0, duration: 0)
                    LinearKeyframe(1.0, duration: ok ? 0.7 : 0.62)
                }
        }
    }
}

extension View {
    func syncRipple(trigger: Int, ok: Bool, from origin: CGPoint) -> some View {
        modifier(SyncRipple(trigger: trigger, ok: ok, origin: origin))
    }
}
