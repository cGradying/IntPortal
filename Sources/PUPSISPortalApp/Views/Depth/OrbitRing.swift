import SwiftUI

/// Portals standing on a ring you orbit. The centered item is the one you
/// step into; the rest recede by depth. ← / → turn the ring one step.
struct OrbitRing<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @Binding var index: Int
    var radius: CGFloat = 320
    @ViewBuilder let content: (Item, _ isFront: Bool) -> Content
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        let count = items.count
        let front = Self.wrap(index, count)
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { k, item in
                content(item, k == front)
                    .modifier(OrbitPlacement(slot: Double(k), angle: Double(index), count: count, radius: radius))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.orbit(reduced: reduceMotion), value: index)
        .focusable()
        .onKeyPress(.leftArrow) { index -= 1; return .handled }
        .onKeyPress(.rightArrow) { index += 1; return .handled }
    }

    static func wrap(_ index: Int, _ count: Int) -> Int {
        count == 0 ? 0 : ((index % count) + count) % count
    }
}

/// Where one ring slot sits for a given (animatable) ring angle, so a turn
/// travels along the circle instead of cutting straight across it.
struct OrbitPlacement: ViewModifier, Animatable {
    let slot: Double
    var angle: Double
    let count: Int
    let radius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    struct Pose: Equatable {
        /// −1 (left) to 1 (right).
        let x: Double
        /// −1 (back) to 1 (front).
        let z: Double
        var scale: Double { 0.5 + 0.25 * (z + 1) }
        var opacity: Double { 0.3 + 0.35 * (z + 1) }
        /// Turned to face the ring's center.
        var yaw: Double { -asin(max(-1, min(1, x))) * 0.4 }
    }

    static func pose(slot: Double, angle: Double, count: Int) -> Pose {
        let theta = (slot - angle) * 2 * .pi / Double(max(count, 1))
        return Pose(x: sin(theta), z: cos(theta))
    }

    func body(content: Content) -> some View {
        let pose = Self.pose(slot: slot, angle: angle, count: count)
        content
            .rotation3DEffect(.radians(pose.yaw), axis: (0, 1, 0), perspective: 0.6)
            .scaleEffect(pose.scale)
            .opacity(pose.opacity)
            .offset(x: pose.x * radius, y: -(1 - pose.scale) * 60)
            .zIndex(pose.z)
    }
}
