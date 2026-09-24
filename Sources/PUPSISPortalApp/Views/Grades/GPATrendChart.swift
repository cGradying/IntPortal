import AppKit
import SwiftUI

/// The GPA trend across terms: a pixel line chart with square markers and
/// dashed guides at 1.00/1.50/2.00. PUP grades run 1.00 (best) to 5.00
/// (worst), so the domain is built low-to-high in GPA terms directly — a
/// better (lower) GPA lands nearer the top of the chart without any extra
/// flip, which is what "inverted axis" means here.
struct GPATrendChart: View {
    /// Oldest first, already filtered to terms with a posted GPA.
    let terms: [GradeReport]
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    private var points: [(label: String, gpa: Double)] {
        terms.map { ($0.termLabel, $0.computedGPA ?? 0) }
    }

    /// Always wide enough to show the three guides, padded a little past
    /// whatever the real data does.
    private var domain: (lo: Double, hi: Double) {
        let values = points.map(\.gpa)
        let lo = min(values.min() ?? 1.0, 1.0) - 0.1
        let hi = max(values.max() ?? 2.0, 2.0) + 0.1
        return (lo, hi)
    }

    private static let guides: [Double] = [1.0, 1.5, 2.0]
    private static let leftMargin: CGFloat = 42
    private static let rightMargin: CGFloat = 12
    private static let topMargin: CGFloat = 10
    private static let bottomMargin: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let (lo, hi) = domain
            let x = xPosition(count: points.count, width: size.width)
            let y = yPosition(lo: lo, hi: hi, height: size.height)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(&context, size: size, x: x, y: y) }
                    .accessibilityHidden(true)

                ForEach(Self.guides, id: \.self) { value in
                    Text(String(format: "%.2f", value))
                        .font(typography.numeric(size: 11))
                        .foregroundStyle(palette.roles.ink3)
                        .position(x: Self.leftMargin - 22, y: y(value))
                }

                let visible = Self.visibleLabelIndices(labels: points.map(\.label), x: points.indices.map(x))
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if visible.contains(index) {
                        // A term label carries a school year — a number
                        // someone must read exactly — so it stays in the
                        // reading face even though the rest of the label is
                        // a word (Legibility Rule: Pixelify's 2/9 blur into
                        // 8/S under 20pt).
                        //
                        // The first and last labels anchor by their leading/
                        // trailing edge instead of centering on their point,
                        // so a long term name (a school year plus "1st Sem")
                        // stays inside the plot instead of overhanging the
                        // sheet's edge.
                        let width = Self.labelWidth(point.label)
                        let centerX: CGFloat =
                            index == 0 ? x(0) + width / 2
                            : index == points.count - 1 ? x(points.count - 1) - width / 2
                            : x(index)
                        Text(point.label)
                            .font(typography.numeric(size: 10))
                            .foregroundStyle(palette.roles.ink3)
                            .fixedSize()
                            .position(x: centerX, y: size.height - Self.bottomMargin + 12)
                    }
                }

                if let last = points.last {
                    Text(String(format: "%.2f", last.gpa))
                        .font(typography.numeric(size: 13, weight: .semibold))
                        .foregroundStyle(palette.roles.ink)
                        .position(x: x(points.count - 1) - 20, y: y(last.gpa) - 12)
                }
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilitySummary(for: terms))
    }

    /// The rendered width of a term label at the axis font size — used both
    /// to anchor the end labels inside the plot and to decide how many
    /// labels can share the axis without overlapping.
    private static func labelWidth(_ text: String) -> CGFloat {
        // Match the reading face the label actually renders in — measuring
        // against the system font under-estimates Source Sans 3, which let
        // labels overlap even though the thinning below said they'd fit.
        // The 1.15x pads for `monospacedDigit()` widening the tabular
        // figures a touch beyond what a plain size lookup reports.
        let font = NSFont(name: "Source Sans 3", size: 10) ?? NSFont.systemFont(ofSize: 10, weight: .medium)
        return (text as NSString).size(withAttributes: [.font: font]).width * 1.15
    }

    /// Which term labels to draw along the x-axis. The first and last
    /// always show (they anchor the plot). Walked left to right, a label
    /// is kept only once its own point is far enough past the last kept
    /// label's edge to clear it — real pixel gaps, not just "every Nth
    /// index", since terms spaced unevenly (or two adjacent ones with very
    /// different name lengths) can't be thinned correctly by index alone.
    /// A trailing pass then re-checks the forced-in last label against
    /// whatever was kept right before it, since forcing it in can put it
    /// closer to its neighbor than the walk allowed for anything else.
    static func visibleLabelIndices(labels: [String], x: [CGFloat]) -> Set<Int> {
        let count = labels.count
        guard count > 2 else { return Set(0..<max(count, 0)) }

        let widths = labels.map(labelWidth)
        let gap: CGFloat = 10

        var kept = [0]
        for i in 1..<count {
            let last = kept[kept.count - 1]
            let needed = widths[last] / 2 + widths[i] / 2 + gap
            if i == count - 1 || x[i] - x[last] >= needed {
                kept.append(i)
            }
        }

        // The last index is always in `kept` (the loop's `i == count - 1`
        // clause guarantees it); if forcing it in left too little room
        // from whatever came before, drop that one rather than the edge.
        while kept.count > 2 {
            let n = kept.count
            let a = kept[n - 2], b = kept[n - 1]
            let needed = widths[a] / 2 + widths[b] / 2 + gap
            guard x[b] - x[a] < needed else { break }
            kept.remove(at: n - 2)
        }

        return Set(kept)
    }

    private func xPosition(count: Int, width: CGFloat) -> (Int) -> CGFloat {
        let span = max(width - Self.leftMargin - Self.rightMargin, 1)
        return { index in
            guard count > 1 else { return Self.leftMargin + span / 2 }
            return Self.leftMargin + CGFloat(index) / CGFloat(count - 1) * span
        }
    }

    private func yPosition(lo: Double, hi: Double, height: CGFloat) -> (Double) -> CGFloat {
        let span = max(height - Self.topMargin - Self.bottomMargin, 1)
        return { value in Self.topMargin + CGFloat((value - lo) / (hi - lo)) * span }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, x: (Int) -> CGFloat, y: (Double) -> CGFloat) {
        let roles = palette.roles

        for guide in Self.guides {
            var dashed = Path()
            dashed.move(to: CGPoint(x: Self.leftMargin, y: y(guide)))
            dashed.addLine(to: CGPoint(x: size.width - Self.rightMargin, y: y(guide)))
            context.stroke(dashed, with: .color(roles.line), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        guard points.count > 1 else { return }

        // Reuses the first subject swatch as the chart's own accent — the
        // trend isn't about any one subject, but the app has no separate
        // "chart" hue and this is what the prototype does too.
        let lineColor = palette.subjectColors[0]

        var line = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: x(index), y: y(point.gpa))
            index == 0 ? line.move(to: p) : line.addLine(to: p)
        }
        context.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 2.5, lineJoin: .miter))

        for (index, point) in points.enumerated() {
            let isLast = index == points.count - 1
            let side: CGFloat = isLast ? 10 : 8
            let rect = CGRect(x: x(index) - side / 2, y: y(point.gpa) - side / 2, width: side, height: side)
            context.fill(Path(rect), with: .color(isLast ? lineColor : roles.sheet))
            context.stroke(Path(rect), with: .color(lineColor), style: StrokeStyle(lineWidth: 2))
        }
    }
}

extension GPATrendChart {
    /// Terms with a posted GPA, oldest first — the only ones a trend line
    /// should plot.
    static func trendTerms(from allTerms: [GradeReport]) -> [GradeReport] {
        allTerms.filter { $0.computedGPA != nil }
    }

    /// A spoken summary: the latest GPA and which way it moved. Lower is
    /// better on PUP's scale, so a numeric drop is announced as "up" — the
    /// plain-language improvement, not the raw arithmetic direction.
    static func accessibilitySummary(for terms: [GradeReport]) -> String {
        let posted = terms.compactMap { term in term.computedGPA.map { (term.termLabel, $0) } }
        guard let latest = posted.last else { return "GPA trend" }

        let base = "GPA trend across \(posted.count) terms. Latest \(String(format: "%.2f", latest.1)) in \(latest.0)."
        guard posted.count >= 2 else { return base }

        let previous = posted[posted.count - 2].1
        let direction: String
        if latest.1 < previous { direction = "up from" }
        else if latest.1 > previous { direction = "down from" }
        else { direction = "unchanged from" }
        return base + " \(direction) \(String(format: "%.2f", previous))."
    }
}
