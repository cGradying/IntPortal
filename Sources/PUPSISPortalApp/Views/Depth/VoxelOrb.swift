import SwiftUI

/// IntAssis' mark. While the model works it becomes a turning voxel cube;
/// otherwise the pixel spark. Under Reduce Motion the cube holds still.
struct VoxelOrb: View {
    var thinking: Bool
    var size: CGFloat = 24
    @Environment(\.palette) private var palette
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if thinking {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let turn = reduceMotion ? 0.12 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    Canvas { ctx, canvas in Self.drawCube(ctx, in: canvas, turn: turn, roles: palette.roles) }
                }
            } else {
                PixelIcon(.spark2, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(thinking ? "IntAssis is thinking" : "IntAssis")
    }

    /// Faces of a unit cube spun `turn` of a full turn about Y and tipped
    /// toward the viewer, painted back to front.
    static func drawCube(_ ctx: GraphicsContext, in size: CGSize, turn: Double, roles: Palette.Roles) {
        let a = turn * 2 * .pi, tilt = -0.5
        let corners: [SIMD3<Double>] = [
            [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1],
        ].map { (p: SIMD3<Double>) in
            let x = p.x * cos(a) + p.z * sin(a), z = -p.x * sin(a) + p.z * cos(a)
            return [x, p.y * cos(tilt) - z * sin(tilt), p.y * sin(tilt) + z * cos(tilt)]
        }
        let s = min(size.width, size.height) * 0.28
        let point = { (i: Int) in CGPoint(x: size.width / 2 + corners[i].x * s, y: size.height / 2 + corners[i].y * s) }
        let faces: [([Int], Color)] = [
            ([4, 5, 6, 7], roles.gold), ([1, 0, 3, 2], roles.gold), ([0, 4, 7, 3], roles.goldInk),
            ([5, 1, 2, 6], roles.goldInk), ([0, 1, 5, 4], roles.goldSoft), ([3, 7, 6, 2], roles.goldInk),
        ]
        for (idx, color) in faces.sorted(by: { a, b in a.0.map { corners[$0].z }.reduce(0, +) < b.0.map { corners[$0].z }.reduce(0, +) }) {
            var path = Path()
            path.addLines(idx.map(point))
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
            ctx.stroke(path, with: .color(roles.menuField), lineWidth: 1.5)
        }
    }
}
