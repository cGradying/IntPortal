import SwiftUI

/// Changing screens moves along the sidebar's order: going down the menu the
/// new screen comes forward out of the page, going up it drops back into it.
/// Depth is drawn as scale plus a small drift, since SwiftUI has no Z.
struct DepthPush: Transition {
    /// +1 going down the menu, −1 going up.
    let direction: Int

    func body(content: Content, phase: TransitionPhase) -> some View {
        let depth: Double = switch phase {
        case .identity: 0
        case .willAppear: -Double(direction)
        case .didDisappear: Double(direction)
        }
        content.modifier(DepthPushFace(depth: depth))
    }
}

/// A screen at a fractional depth: negative is behind the page, positive in
/// front of it, 0 in place.
struct DepthPushFace: ViewModifier, Animatable {
    var depth: Double

    var animatableData: Double {
        get { depth }
        set { depth = newValue }
    }

    /// 24pt of travel seen through the page: about 4% of scale per step.
    static func scale(depth: Double) -> Double { 1 + 0.04 * depth }

    func body(content: Content) -> some View {
        content
            .scaleEffect(Self.scale(depth: depth))
            .offset(y: -8 * depth)
            .opacity(1 - min(abs(depth), 1))
    }
}

extension View {
    func depthPush(direction: Int, reduced: Bool) -> some View {
        transition(reduced ? AnyTransition.opacity : AnyTransition(DepthPush(direction: direction)))
    }
}
