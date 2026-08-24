import SwiftUI

/// Shown before a study session starts — pick how to study this deck today.
/// Mode is a per-session choice, never stored on the deck, so the same cards
/// support every mode without regenerating anything.
struct QuizModePicker: View {
    let deck: QuizDeck
    let onPick: (QuizMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(deck.name).font(.headline)
                Text("\(deck.dueCards().count) card(s) due").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(QuizMode.allCases) { mode in
                    modeButton(mode)
                }
            }
            .padding(.horizontal, 20)

            Button("Cancel") { onCancel() }
                .padding(.bottom, 20)
        }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 640)
    }

    private func modeButton(_ mode: QuizMode) -> some View {
        let enabled = deck.cards.count >= mode.minCards
        return Button {
            onPick(mode)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: mode.symbol).font(.title2)
                Text(mode.label).font(.callout.weight(.medium)).multilineTextAlignment(.center)
                if !enabled {
                    Text("Needs \u{2265}\(mode.minCards) cards").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
