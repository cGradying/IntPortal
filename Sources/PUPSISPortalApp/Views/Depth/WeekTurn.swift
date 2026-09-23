import SwiftUI

/// Paging Schedule turns the grid like a cube face: the next week comes in
/// from the right, the previous week from the left, both turning about the
/// cube's center so the two faces stay joined at the edge.
struct WeekTurn: Transition {
    /// +1 toward the future, −1 toward the past.
    let direction: Int
    /// The face's width, which sets the cube's depth.
    let width: CGFloat

    /// Degrees about Y for a face at `offset`: 0 in front, −1 turned away
    /// to the past side, +1 to the future side.
    static func angle(offset: Double) -> Double { offset * 90 }

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(WeekTurnFace(offset: phase.isIdentity ? 0 : Double(phase == .willAppear ? direction : -direction), width: width))
    }
}

/// One cube face at a fractional offset, so the turn can be scrubbed.
struct WeekTurnFace: ViewModifier, Animatable {
    var offset: Double
    let width: CGFloat

    var animatableData: Double {
        get { offset }
        set { offset = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(WeekTurn.angle(offset: offset)), axis: (0, 1, 0),
                              anchor: .center, anchorZ: -width / 2, perspective: 0.35)
            .opacity(abs(offset) > 0.98 ? 0 : 1)
    }
}

extension View {
    /// Keyed by the week (`.id(weekOffset)`), with `Motion.turn` driving it.
    /// Under Reduce Motion the weeks swap with a plain crossfade.
    func weekTurn(direction: Int, width: CGFloat, reduced: Bool) -> some View {
        transition(reduced ? AnyTransition.opacity : AnyTransition(WeekTurn(direction: direction, width: width)))
    }
}
