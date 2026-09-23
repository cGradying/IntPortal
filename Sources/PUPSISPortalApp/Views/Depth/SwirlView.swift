import SwiftUI

/// The portal's maroon-to-gold dithered swirl. `speed` shows activity (sync
/// running, the warp), `lit` fades it in, `cell` is the pixel size. Frozen
/// under Reduce Motion; a Canvas ramp when Metal is unavailable.
struct SwirlView: View {
    var speed: Double = 1
    var lit: Double = 1
    var cell: Double = 3
    /// Pins the clock, for snapshots.
    var time: Double?
    @Environment(\.reduceMotion) private var reduceMotion

    static let ramp: [Color] = [0x170509, 0x540A1C, 0x941C30, 0xCCA128, 0xFAEBB3].map { Color(rgb: $0) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || time != nil)) { context in
            let t = time ?? (reduceMotion ? 1.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            GeometryReader { geo in
                if let library = Shaders.library {
                    Rectangle().colorEffect(library.portalSwirl(
                        .float2(geo.size), .float(t), .float(speed), .float(lit), .float(cell),
                        .color(Self.ramp[0]), .color(Self.ramp[1]), .color(Self.ramp[2]), .color(Self.ramp[3]), .color(Self.ramp[4])
                    ))
                } else {
                    Self.fallback(lit: lit)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Five dithered bands, center brightest: the swirl without motion.
    static func fallback(lit: Double) -> some View {
        Canvas { context, size in
            let cell: CGFloat = 3
            for y in stride(from: 0, to: size.height, by: cell) {
                for x in stride(from: 0, to: size.width, by: cell) {
                    let u = x / size.width - 0.5, v = y / size.height - 0.5
                    let d = (u * u * 1.5 + v * v * 0.7).squareRoot()
                    let threshold = Double(Bayer.matrix[Int(y / cell) % 4][Int(x / cell) % 4]) / 16
                    let k = min(4, max(0, Int(((0.9 - d * 1.6) * lit) * 4 + threshold - 0.5)))
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(ramp[k]))
                }
            }
        }
    }
}
