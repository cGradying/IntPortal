import SwiftUI

/// Theme, font (reading text only — display stays Pixelify Sans), UI scale,
/// notes sidebar side, and per-subject colors.
struct AppearancePane: View {
    @ObservedObject var preferences: Preferences
    /// Subjects the user can actually recolor: whatever is on screen right
    /// now — passed in rather than read off a live `PortalController`, same
    /// decomposition `SettingsScreen` uses everywhere else.
    let sessions: [ClassSession]

    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.reduceMotion) private var reduceMotion

    private var subjectCodes: [String] { ClassSession.subjectCodes(in: sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Theme") {
                themeSwatchRow
                    .padding(.vertical, 4)
                SettingsRow(label: "Font") {
                    Picker("", selection: $preferences.fontChoice) {
                        ForEach(FontChoice.allCases) { choice in
                            // Previews the *reading* face (Source Sans 3, or
                            // the family itself) at reading size — display
                            // stays Pixelify regardless of this pick, so
                            // previewing it here would show the wrong thing.
                            Text(choice.label)
                                .font(Typography(choice).reading(size: 15))
                                .tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                }
                SettingsRow(label: "UI Scale") {
                    HStack(spacing: 8) {
                        Text("\(Int(preferences.uiScale * 100))%").foregroundStyle(.secondary)
                        Stepper("", value: $preferences.uiScale, in: Preferences.uiScaleRange, step: Preferences.uiScaleStep)
                            .labelsHidden()
                    }
                }
                .help("\u{2318}+ / \u{2318}\u{2212} anywhere, \u{2325}\u{2318}0 to reset")
                if preferences.uiScale != 1.0 {
                    Button("Reset to 100%") { preferences.resetUIScale() }
                        .buttonStyle(.pixelSmall)
                        .font(.caption)
                }
            }

            SettingsSection(title: "Layout") {
                SettingsRow(label: "Notes sidebar") {
                    Picker("", selection: $preferences.notebookSidebarOnLeft) {
                        Text("Right").tag(false)
                        Text("Left").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                }
            }

            SettingsSection(title: "Subject Colors", footer: "Each row has its own Reset button.") {
                if subjectCodes.isEmpty {
                    Text("Subjects appear here once your schedule loads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subjectCodes, id: \.self) { code in
                        SubjectColorRow(code: code, preferences: preferences, palette: palette)
                    }
                }
            }

            SettingsResetButton {
                preferences.theme = .auto
                preferences.fontChoice = .system
                preferences.uiScale = 1.0
                preferences.notebookSidebarOnLeft = false
            }

            SettingsTechnicalSection(rows: [
                ("Accent", palette.accent.hex ?? "—"),
                ("Canvas top", palette.canvasTop.hex ?? "—"),
                ("Canvas bottom", palette.canvasBottom.hex ?? "—"),
                ("Font family", preferences.fontChoice.familyName ?? "system"),
                ("UI scale factor", String(format: "%.2f", preferences.uiScale)),
            ])
        }
    }

    /// 14 themes is too many for a bare row of unlabeled circles — a named
    /// card grid, each previewing the theme it names (its own accent dot on
    /// its own canvas, so a dark theme reads as dark before it's applied).
    private var themeSwatchRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
            ForEach(ThemeChoice.allCases) { choice in
                let choicePalette = choice.palette(for: systemScheme)
                let selected = preferences.theme == choice
                Button { preferences.theme = choice } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            // The shell this room paints: menu field, ground, action.
                            HStack(spacing: 0) {
                                choicePalette.roles.menuField.frame(width: 8)
                                ZStack {
                                    choicePalette.roles.ground
                                    Rectangle().fill(choicePalette.roles.action).frame(width: 8, height: 8)
                                }
                            }
                            .frame(width: 26, height: 18)
                            .overlay(Rectangle().strokeBorder(.primary.opacity(0.12)))
                            Text(choice.label).font(.caption).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        if selected {
                            DitherRule(color: palette.accent, reduced: reduceMotion, height: 2)
                        }
                    }
                    .background(palette.accent.opacity(selected ? 0.12 : 0), in: PixelNotch())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.label)
            }
        }
    }
}

private struct SubjectColorRow: View {
    let code: String
    @ObservedObject var preferences: Preferences
    let palette: Palette
    @Environment(\.typography) private var typography

    var body: some View {
        HStack(spacing: 12) {
            // Binding rather than onChange: ColorPicker writes continuously
            // while the user drags, and the swatch has to follow.
            ColorPicker(
                selection: Binding(
                    get: { preferences.color(for: code, in: palette) },
                    set: { preferences.setColor($0, for: code) }
                ),
                supportsOpacity: false
            ) {
                Text(code).font(typography.blockCode)
            }

            Spacer()

            Button("Reset") { preferences.resetColor(for: code) }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(!preferences.hasCustomColor(for: code))
        }
        .padding(.vertical, 2)
    }
}
