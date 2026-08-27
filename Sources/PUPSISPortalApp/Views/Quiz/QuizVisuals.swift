import SwiftUI

/// Shared presentation pieces for every study mode — a card-reveal
/// transition and small procedural pixel-art feedback accents. Both are
/// code-drawn (a gradient sweep, a `Canvas`-rasterized bitmap) rather than
/// image assets: no asset-catalog entries to add, fully themeable, and
/// trivial to extend with another badge later.

// MARK: Card generation transition

/// Applied to a session's card content, keyed by whatever identifies "which
/// card/round is showing" (a card id, a round counter). Changing that key
/// gives the view a fresh identity, which is what makes this work with no
/// manual state-reset plumbing: SwiftUI treats it as a new view, `@State`
/// starts over, and `onAppear` fires again.
///
/// Same reveal concept as the note editor's AI text insertion
/// (`WebNoteEditor.swift:707-780`, `notes-editor/src/editor.js:975-1042`) —
/// a settle-in ease (blur → sharp, a slight drop, opacity in) plus one
/// accent-colored sweep crossing once — not a spinning rainbow halo. The
/// timing curve is the literal CSS `cubic-bezier(.22,.85,.32,1)` the note
/// editor uses (`pupFadeWordIn`), not an approximation: `Animation
/// .timingCurve` takes the same four control points.
private struct CardGenerationTransition: ViewModifier {
    let key: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resolved = false

    func body(content: Content) -> some View {
        content
            .opacity(resolved ? 1 : 0)
            .offset(y: resolved ? 0 : 4)
            .blur(radius: resolved || reduceMotion ? 0 : 10)
            .overlay { if !resolved, !reduceMotion { GenerationSweep() } }
            .id(key)
            .onAppear {
                resolved = false
                withAnimation(settleAnimation) { resolved = true }
            }
    }

    /// Mirrors `WebNoteEditor`'s own `@media (prefers-reduced-motion:
    /// reduce)` fallback (`pupFadeWordInReduced`) — instant-feeling linear
    /// fade, no blur/offset/sweep to sit through.
    private var settleAnimation: Animation {
        reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.22, 0.85, 0.32, 1, duration: 0.56)
    }
}

/// One accent-tinted beam crossing the card once — the "AI wrote this"
/// signal, drawn from the active theme rather than a fixed palette so it
/// reads correctly whatever theme/accent the student has picked. Mirrors
/// `.pup-sweep-beam` (`WebNoteEditor.swift:760-768`): a soft gradient bar,
/// travels start-to-end, once, then gone — not a repeating/rotating effect.
private struct GenerationSweep: View {
    @Environment(\.palette) private var palette
    @State private var progress: CGFloat = -0.4

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, palette.accent.opacity(0.5), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.4)
            .blendMode(.plusLighter)
            .offset(x: proxy.size.width * progress)
        }
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 0.56)) { progress = 1.0 }
        }
    }
}

extension View {
    /// Fade/blur/drop out, then resolve back in through `GenerationSweep` —
    /// call whenever the shown card or round changes.
    func cardGenerationTransition(key: AnyHashable) -> some View {
        modifier(CardGenerationTransition(key: key))
    }
}

/// Quiz correctness signals, deliberately independent of the active room's
/// own accent — a themed accent risks visually colliding with "this answer
/// was right" (confirmed a real problem in Matrix, whose own accent is
/// itself phosphor green). Fixed, not palette-derived, the way a real-world
/// green-check/red-X convention is fixed regardless of surrounding decor.
extension Color {
    static let quizSuccess = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let quizDanger = Color(red: 0.910, green: 0.298, blue: 0.235)
}

// MARK: Pixel-art feedback badges

/// What a badge shows — each is a small hand-drawn bitmap, `1` filled, laid
/// out row by row for readability. New badges are just another case.
enum PixelBadgeKind {
    case correct
    case incorrect
    case streak

    fileprivate var grid: [[Bool]] {
        switch self {
        case .correct:
            Self.grid([
                "0000000",
                "0000010",
                "0000100",
                "0001000",
                "1010000",
                "0100000",
                "0000000",
            ])
        case .incorrect:
            Self.grid([
                "1000001",
                "0100010",
                "0010100",
                "0001000",
                "0010100",
                "0100010",
                "1000001",
            ])
        case .streak:
            Self.grid([
                "0001000",
                "0001000",
                "0011100",
                "0111110",
                "1111111",
                "1111111",
                "0111110",
                "0011100",
                "0001000",
            ])
        }
    }

    var color: Color {
        switch self {
        case .correct: .quizSuccess
        case .incorrect: .quizDanger
        case .streak: .orange
        }
    }

    /// A `Canvas`-drawn bitmap has nothing for VoiceOver to read on its own —
    /// this is the only signal a screen-reader user gets that an answer was
    /// right or wrong.
    var accessibilityLabel: String {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Incorrect"
        case .streak: "Streak"
        }
    }

    private static func grid(_ rows: [String]) -> [[Bool]] {
        rows.map { row in row.map { $0 == "1" } }
    }
}

/// A pixel bitmap that fills in square by square on appear — one `Canvas`,
/// no image assets. `key` gives it a fresh identity (and so a fresh
/// fill-in animation) each time it's shown for a new result, the same
/// pattern `CardGenerationTransition` uses.
struct PixelBadge: View {
    let kind: PixelBadgeKind
    var key: AnyHashable = UUID()
    @State private var revealed = 0

    var body: some View {
        Canvas { context, size in
            let grid = kind.grid
            let rows = grid.count
            let cols = grid.first?.count ?? 0
            guard rows > 0, cols > 0 else { return }
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let originX = (size.width - cell * CGFloat(cols)) / 2
            let originY = (size.height - cell * CGFloat(rows)) / 2

            var index = 0
            for row in 0..<rows {
                for col in 0..<cols {
                    defer { index += 1 }
                    guard grid[row][col], index < revealed else { continue }
                    let rect = CGRect(
                        x: originX + CGFloat(col) * cell, y: originY + CGFloat(row) * cell,
                        width: cell, height: cell
                    ).insetBy(dx: 1, dy: 1)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(kind.color))
                }
            }
        }
        .id(key)
        .onAppear { animateReveal() }
        .accessibilityElement()
        .accessibilityLabel(kind.accessibilityLabel)
    }

    private func animateReveal() {
        let total = kind.grid.flatMap { $0 }.filter { $0 }.count
        revealed = 0
        Task {
            for step in 0...total {
                revealed = step
                try? await Task.sleep(nanoseconds: 14_000_000)
            }
        }
    }
}

// MARK: Progress ring

/// A stroked-circle progress indicator — real fractions only (queue
/// position, mastery), never a stand-in for content that isn't there. Used
/// on the deck browser's stat cards and in the session header, both driven
/// by numbers the store actually computed.
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: Shared session chrome

/// The top bar every session mode shows — deck name, a due-queue progress
/// ring, a running this-session correct tally, Done. One copy instead of
/// five near-identical `HStack`s.
struct QuizSessionHeader: View {
    let title: String
    let position: Int
    let total: Int
    var correct: Int = 0
    // No default — `.accentColor` here was the *system* accent, not the
    // room's own, and MatchingSession was the one call site quietly relying
    // on it instead of a real palette color. Every caller says one now.
    let ringColor: Color
    let onDone: () -> Void

    var body: some View {
        HStack {
            Button("Done") { onDone() }
            Spacer()
            VStack(spacing: 3) {
                Text(title).font(.headline)
                HStack(spacing: 6) {
                    ProgressRing(progress: total > 0 ? Double(position) / Double(total) : 0, color: ringColor, lineWidth: 3)
                        .frame(width: 14, height: 14)
                    Text("\(min(position, max(total, position))) / \(total)")
                        .font(.caption).foregroundStyle(.secondary)
                    if correct > 0 {
                        Text("· \(correct) correct").font(.caption).foregroundStyle(Color.quizSuccess)
                    }
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 1) // balances the Done button so the title stays centered
        }
        .padding([.horizontal, .top], 16)
    }
}

/// A deck tile for the browser's category dashboard — subject-tinted glass,
/// a mastery ring (real fraction: `1 - due/total`, never a placeholder), and
/// due/total counts. `featured: true` is the hero-strip's larger rendition
/// of the same tile, not a different component.
struct DeckStatCard: View {
    let deck: QuizDeck
    let color: Color
    var featured: Bool = false
    let onTap: () -> Void

    private var due: Int { deck.dueCards().count }
    private var total: Int { deck.cards.count }
    private var mastery: Double { total > 0 ? 1 - Double(due) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(deck.name)
                    .font(featured ? .title3.weight(.semibold) : .headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                ZStack {
                    ProgressRing(progress: mastery, color: color, lineWidth: featured ? 3.5 : 2.5)
                    Text("\(Int(mastery * 100))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                }
                .frame(width: featured ? 52 : 40, height: featured ? 52 : 40)
            }
            HStack(spacing: 8) {
                statBadge("\(total)", label: "cards", emphasized: false)
                if due > 0 {
                    statBadge("\(due)", label: "due", emphasized: true)
                } else {
                    Text("All caught up").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(featured ? 20 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(featured ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: featured ? 20 : 12))
        .overlay(RoundedRectangle(cornerRadius: featured ? 20 : 12).strokeBorder(color.opacity(0.25)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func statBadge(_ value: String, label: String, emphasized: Bool) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.caption.weight(.semibold))
            Text(label).font(.caption2)
        }
        .foregroundStyle(emphasized ? color : .secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(emphasized ? color.opacity(0.16) : .secondary.opacity(0.12), in: .capsule)
    }
}

/// "Nothing due" — every mode's empty state.
struct QuizEmptyState: View {
    let message: String

    var body: some View {
        Spacer()
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 40)).foregroundStyle(Color.quizSuccess)
            Text(message).foregroundStyle(.secondary)
        }
        Spacer()
    }
}

/// "Session complete" — every mode's finished state.
struct QuizCompleteState: View {
    let onDone: () -> Void

    var body: some View {
        Spacer()
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Color.quizSuccess)
            Text("Session complete.").foregroundStyle(.secondary)
            Button("Done") { onDone() }
        }
        Spacer()
    }
}
