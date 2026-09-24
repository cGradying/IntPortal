import SwiftUI

/// Shared row/section chrome every Settings pane builds its rows from — a
/// pixel `Sheet` per group of rows (spec 07: "one or two sheets of rows"),
/// each row fixed label-left, control-right. Replaces `SettingsView`'s old
/// `compactSection`/`compactRow` (glass, collapsible) now that Settings is a
/// screen: no glass, no collapsing, just sheets.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var rows: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Sheet(label: title) {
                VStack(alignment: .leading, spacing: 0) { rows }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
            }
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(palette.roles.ink3)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.top, Spacing.xs)
            }
        }
    }
}

/// One row: a fixed-width label on the left, its control on the right, a
/// hairline underneath. Pass a control with `.labelsHidden()` already
/// applied — native controls draw their own label otherwise, repeating the
/// text this row already shows.
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var control: Content
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        HStack {
            Text(label).font(typography.reading(size: 13, weight: .medium))
            Spacer(minLength: 12)
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.roles.line).frame(height: 1)
        }
    }
}

/// Always-visible technical facts for a pane — real paths, identifiers, and
/// raw statuses, monospaced and selectable.
struct SettingsTechnicalSection: View {
    let rows: [(String, String)]

    var body: some View {
        SettingsSection(title: "Technical Details") {
            ForEach(rows, id: \.0) { row in
                SettingsRow(label: row.0) {
                    Text(row.1)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

/// A pane's "Reset This Pane to Defaults" button — same small pixel
/// secondary button on every pane that has one.
struct SettingsResetButton: View {
    let action: () -> Void

    var body: some View {
        Button("Reset This Pane to Defaults", action: action)
            .buttonStyle(.pixelSmall)
    }
}

/// This app's one recurring "you are here" mark: a thin, idly-drifting
/// pixel-dither line. Same `DitherFill`/`TimelineView` pairing the old home
/// launcher used for its ambient wave, scaled down to a line — the theme
/// picker's selected card here. Idles with a slow drift rather than sitting
/// static; pauses to one still frame under Reduce Motion rather than merely
/// slowing down.
struct DitherRule: View {
    let color: Color
    let reduced: Bool
    var height: CGFloat = 2
    var intensity: Double = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: reduced ? nil : 0.16, paused: reduced)) { context in
            DitherFill(
                color: color,
                cell: 2,
                ramp: .wave(intensity),
                phase: reduced ? 0 : context.date.timeIntervalSinceReferenceDate * 0.5
            )
        }
        .frame(height: height)
    }
}
