import SwiftUI

/// One "Due soon" row: a maroon-strip date tile (DESIGN.md's "Date tile")
/// plus the item's topic, subject and type. Exams also show days left, in
/// the `bad` role — the Now Rule's counterpart for urgency rather than the
/// present moment.
struct DueSoonTile: View {
    let item: SyllabusItem
    let now: Date
    var last = false
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    private var daysLeft: Int? {
        guard let date = item.date else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day
    }

    var body: some View {
        HStack(spacing: 10) {
            dateTile
            VStack(alignment: .leading, spacing: 1) {
                Text(item.topic).font(typography.footer.weight(.semibold)).lineLimit(1)
                Text("\(item.subjectCode) · \(item.type.label.lowercased())")
                    .font(typography.detailMeta)
                    .foregroundStyle(palette.roles.ink3)
            }
            Spacer(minLength: 4)
            if item.type == .exam, let daysLeft {
                Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s")")
                    .font(typography.numeric(size: 13, weight: .semibold))
                    .foregroundStyle(palette.roles.bad)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(palette.roles.line).frame(height: 1).opacity(0.6) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var label = "\(item.topic), \(item.subjectCode), \(item.type.label)"
        if item.type == .exam, let daysLeft { label += ", \(daysLeft) days left" }
        return label
    }

    private var dateTile: some View {
        VStack(spacing: 0) {
            Text(Self.month.string(from: item.date ?? now))
                .font(typography.display(size: 9))
                .tracking(1)
                .foregroundStyle(palette.roles.onMenu)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(palette.roles.menuField)
            Text(Self.day.string(from: item.date ?? now))
                .font(typography.numeric(size: 15, weight: .bold))
                .foregroundStyle(palette.roles.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(palette.roles.sheet)
        }
        .frame(width: 34)
        .clipShape(PixelNotch())
        .overlay(PixelNotch().strokeBorder(palette.roles.line2, lineWidth: 1))
    }

    private static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
}
