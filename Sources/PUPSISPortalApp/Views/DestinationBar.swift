import SwiftUI

/// The floating "dynamic island" navigation pill: one glass capsule, top-centre,
/// with a segment per destination. Replaces the sidebar — nav chrome floating
/// over the content, which is exactly the layer glass belongs to (see the
/// `liquid-glass` skill). No tint: that's reserved for the now-line.
struct DestinationBar: View {
    @Binding var selection: Destination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    private static let items: [Destination] = [.schedule, .today, .grades]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items) { item in
                segment(item)
            }
        }
        .padding(4)
        .glassCapsule()
        .animation(Motion.selection(reduced: reduceMotion), value: selection)
    }

    private func segment(_ item: Destination) -> some View {
        let isSelected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(item.title)
                    .font(Theme.Typo.dayName)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            // Neutral highlight, not accent — the selected segment is emphasis,
            // not the semantic tint the now-line owns.
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background {
                if isSelected {
                    Capsule()
                        .fill(.primary.opacity(0.12))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
