import SwiftUI

/// The void's colors: fixed, one world, whatever the app theme.
enum VoidPalette {
    static let top = Color(rgb: 0x07050A)
    static let bottom = Color(rgb: 0x12070E)
    static let obsidian = Color(rgb: 0x170B1A)
    static let obsidianHi = Color(rgb: 0x34203F)
    static let obsidianLo = Color(rgb: 0x060307)
    static let fleck = Color(rgb: 0x4A2C58)
    static let dimObsidian = Color(rgb: 0x0E0710)
    static let dimHi = Color(rgb: 0x1C1220)
    static let text = Color(rgb: 0xEDE4DA)
    static let textDim = Color(rgb: 0xB9A9B2)
    static let panel = Color(rgb: 0x120B10)
    static let panelLine = Color(rgb: 0x3A2530)
    static let goldText = Color(rgb: 0xF6E7B0)
    static let goldLine = Color(rgb: 0xC9A227)
}

/// A seeded source of stable "random" numbers, so the void draws the same
/// flecks and motes every frame and every launch.
struct Seeds {
    let values: [Double]
    init(count: Int, seed: UInt32 = 42) {
        var s = seed
        values = (0..<count).map { _ in
            s = s &* 1_664_525 &+ 1_013_904_223
            return Double(s >> 8) / Double(1 << 24)
        }
    }
    subscript(i: Int) -> Double { values[((i % values.count) + values.count) % values.count] }
}

/// The obsidian frame: 6 blocks wide, 8 tall, drawn block by block. `formed`
/// drops blocks in around the perimeter; `live` frames hold the swirl, locked
/// ones a dark speckled pane.
struct PortalFrame: View {
    var block: CGFloat
    var formed: Double = 1
    var lit: Double = 1
    var live: Bool
    var speed: Double = 1
    var cell: Double = 3

    private static let perimeter: [(Int, Int)] = {
        var p: [(Int, Int)] = []
        for c in 0..<6 { p.append((c, 7)) }
        for r in stride(from: 6, through: 0, by: -1) { p.append((5, r)) }
        for c in stride(from: 4, through: 0, by: -1) { p.append((c, 0)) }
        for r in 1...6 { p.append((0, r)) }
        return p
    }()
    private static let seeds = Seeds(count: 200)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if lit > 0, live {
                SwirlView(speed: speed, lit: lit, cell: cell)
                    .frame(width: 4 * block, height: 6 * block)
                    .offset(x: block, y: block)
                    .background(alignment: .center) {
                        Circle()
                            .fill(RadialGradient(colors: [VoidPalette.goldLine.opacity(0.22 * lit), .clear], center: .center, startRadius: block, endRadius: 7 * block))
                            .frame(width: 14 * block, height: 14 * block)
                            .offset(x: -2 * block, y: -3 * block)
                            .allowsHitTesting(false)
                    }
            } else if !live, formed >= 1 {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: 0x0B060D)))
                    let u = max(2, (block / 6).rounded())
                    for k in 0..<40 {
                        let x = Self.seeds[k * 3] * (size.width - u), y = Self.seeds[k * 5 + 1] * (size.height - u)
                        ctx.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: u, height: u)), with: .color(VoidPalette.dimHi))
                    }
                }
                .frame(width: 4 * block, height: 6 * block)
                .offset(x: block, y: block)
            }
            Canvas { ctx, _ in
                let count = Double(Self.perimeter.count) * formed
                let full = Int(count), frac = count - Double(full)
                for (i, cr) in Self.perimeter.enumerated() where Double(i) < count.rounded(.up) {
                    var y = CGFloat(cr.1) * block
                    var alpha = 1.0
                    if i == full { alpha = frac; y -= CGFloat(1 - frac) * block * 1.6 }
                    drawBlock(ctx, at: CGPoint(x: CGFloat(cr.0) * block, y: y), seed: i, alpha: alpha)
                }
            }
            .frame(width: 6 * block, height: 8 * block)
        }
        .frame(width: 6 * block, height: 8 * block, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func drawBlock(_ ctx: GraphicsContext, at p: CGPoint, seed: Int, alpha: Double) {
        var ctx = ctx
        ctx.opacity = alpha
        let b = block, u = max(2, (b / 8).rounded())
        ctx.fill(Path(CGRect(x: p.x, y: p.y, width: b, height: b)), with: .color(live ? VoidPalette.obsidian : VoidPalette.dimObsidian))
        ctx.fill(Path(CGRect(x: p.x, y: p.y, width: b, height: u)), with: .color(live ? VoidPalette.obsidianHi : VoidPalette.dimHi))
        ctx.fill(Path(CGRect(x: p.x, y: p.y, width: u, height: b)), with: .color(live ? VoidPalette.obsidianHi : VoidPalette.dimHi))
        ctx.fill(Path(CGRect(x: p.x, y: p.y + b - u, width: b, height: u)), with: .color(VoidPalette.obsidianLo))
        ctx.fill(Path(CGRect(x: p.x + b - u, y: p.y, width: u, height: b)), with: .color(VoidPalette.obsidianLo))
        for k in 0..<3 {
            let a = Self.seeds[seed * 7 + k * 13], c = Self.seeds[seed * 11 + k * 17]
            ctx.fill(Path(CGRect(x: p.x + u + (a * (b - 3 * u)).rounded(), y: p.y + u + (c * (b - 3 * u)).rounded(), width: u, height: u)),
                     with: .color(live ? VoidPalette.fleck : Color(rgb: 0x150D18)))
        }
    }
}

/// The void behind everything: a vertical gradient and slow-rising motes,
/// some gold ones drifting toward the portal once it's lit.
struct VoidBackdrop: View {
    var time: Double
    var lit: Double
    var rising: Double = 1
    var focus: CGPoint
    private static let seeds = Seeds(count: 400, seed: 7)

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [VoidPalette.top, VoidPalette.bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for i in 0..<70 {
                let speed = 0.01 + Self.seeds[i * 5] * 0.03
                let gold = Self.seeds[i * 5 + 1] < 0.35
                let big = Self.seeds[i * 5 + 2] < 0.3
                var y = (Self.seeds[i * 5 + 3] - time * speed * rising).truncatingRemainder(dividingBy: 1)
                if y < 0 { y += 1 }
                var x = Self.seeds[i * 5 + 4] * size.width
                if gold { x += (focus.x - x) * 0.08 * lit }
                let s: CGFloat = big ? 4 : 2
                ctx.fill(Path(CGRect(x: x.rounded(), y: (y * size.height).rounded(), width: s, height: s)),
                         with: .color(gold ? Color(rgb: 0xE6C45A).opacity(0.25 + 0.5 * lit) : Color(rgb: 0xAA96AA).opacity(0.35)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The isometric 5×5 platform the student stands on, and the student.
struct PlatformAndFigure: View {
    var block: CGFloat
    var lit: Double
    /// The platform sits behind the portal and the student in front of it,
    /// so each is drawn as its own layer.
    var drawsPlatform = true
    var drawsFigure = true
    private static let seeds = Seeds(count: 200, seed: 3)
    private static let figure = ["..hhhh..", "..hhhh..", "..hhhh..", "...ss...", ".mmmmmm.", "mmmmmmmm", "m.mmmm.m", "s.mmmm.s", "..pppp..", "..p..p..", "..p..p..", "..k..k.."]
    private static let figureColors: [Character: Color] = [
        "h": Color(rgb: 0x1A1012), "s": Color(rgb: 0xB9805F), "m": Color(rgb: 0x7A1128), "p": Color(rgb: 0x222840), "k": Color(rgb: 0x0D090B),
    ]

    var body: some View {
        Canvas { ctx, size in
            let a = (block * 0.95).rounded(), d = (block * 0.7).rounded(), n = 5
            let ox = size.width / 2, oy = size.height - (a * CGFloat(n) + d)
            for s in 0...(2 * (n - 1)) where drawsPlatform {
                for i in 0..<n {
                    let j = s - i
                    guard j >= 0, j < n else { continue }
                    let x = ox + CGFloat(i - j) * a, y = oy + CGFloat(i + j) * a / 2
                    let k = Self.seeds[i * 5 + j]
                    let glow = lit * max(0, 1 - hypot(Double(i) - 1.5, Double(j) - 1.5) / 3.2)
                    let top = Color(red: (38 + k * 10 + glow * 70) / 255, green: (26 + k * 6 + glow * 40) / 255, blue: (34 + k * 8 + glow * 8) / 255)
                    var tile = Path()
                    tile.addLines([CGPoint(x: x, y: y), CGPoint(x: x + a, y: y + a / 2), CGPoint(x: x, y: y + a), CGPoint(x: x - a, y: y + a / 2)])
                    ctx.fill(tile, with: .color(top))
                    if i == n - 1 {
                        var side = Path()
                        side.addLines([CGPoint(x: x + a, y: y + a / 2), CGPoint(x: x, y: y + a), CGPoint(x: x, y: y + a + d), CGPoint(x: x + a, y: y + a / 2 + d)])
                        ctx.fill(side, with: .color(Color(rgb: 0x1D1217)))
                    }
                    if j == n - 1 {
                        var side = Path()
                        side.addLines([CGPoint(x: x - a, y: y + a / 2), CGPoint(x: x, y: y + a), CGPoint(x: x, y: y + a + d), CGPoint(x: x - a, y: y + a / 2 + d)])
                        ctx.fill(side, with: .color(Color(rgb: 0x291921)))
                    }
                }
            }
            guard drawsFigure else { return }
            let u = max(2, (block / 5).rounded())
            let fx = (ox - 4 * u).rounded(), fy = oy + 2 * a + 0.55 * block - 12 * u
            for (row, line) in Self.figure.enumerated() {
                for (col, ch) in line.enumerated() {
                    guard let c = Self.figureColors[ch] else { continue }
                    ctx.fill(Path(CGRect(x: fx + CGFloat(col) * u, y: fy + CGFloat(row) * u, width: u, height: u)), with: .color(c))
                }
            }
        }
        .frame(width: block * 10, height: block * 6)
        .accessibilityHidden(true)
    }
}
