import SwiftUI
import AppKit

/// A complete set of colors. Values only, no behavior worth speaking of —
/// changing theme is swapping the whole struct, which is why these stopped
/// being statics: a `static let` can't re-render anything.
struct Palette: Equatable {
    let accent: Color
    let secondary: Color
    let canvasTop: Color
    let canvasBottom: Color
    let gridLine: Color
    /// Default colour of the strip around an online class, before any
    /// per-subject override. Theme-aware so it reads against that theme's block
    /// fills — a value the user can still change per subject in `Preferences`.
    let onlineStrip: Color
    /// Per-subject block colors, indexed deterministically by `color(for:)`.
    let subjectColors: [Color]

    /// The one tint with a job: it marks the present moment and nothing else.
    /// Apple's material guidance is that a tint should carry meaning rather
    /// than decorate, so this stays exclusive to the now-line.
    var nowTint: Color { accent }

    /// Glass needs something underneath it to bend. A flat fill refracts into
    /// a flat fill and the effect reads as a grey box, so the canvas carries a
    /// slow wash — low enough contrast that it never competes with the blocks.
    var canvasWash: LinearGradient {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Stable across launches — `Hashable` seeds randomly per process, which
    /// would repaint every subject a different color each run.
    ///
    /// This is the *default*. A user override lives in `Preferences` and wins
    /// over it; go through `Preferences.color(for:in:)` at call sites.
    func color(for subjectCode: String) -> Color {
        let seed = subjectCode.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return subjectColors[seed % subjectColors.count]
    }

    /// Menus can only show text reliably — a coloured circle in a menu item
    /// renders as a template image — so the palette slots have names.
    static func colorName(at index: Int) -> String {
        ["Maroon", "Rust", "Gold", "Plum", "Forest", "Slate"][index % 6]
    }
}

extension Palette {
    /// PUP maroon and gold on warm paper.
    static let pupMaroon = Palette(
        accent: Color(red: 0.478, green: 0.067, blue: 0.157),
        secondary: Color(red: 0.788, green: 0.635, blue: 0.153),
        canvasTop: Color(red: 0.988, green: 0.984, blue: 0.980),
        canvasBottom: Color(red: 0.949, green: 0.929, blue: 0.925),
        gridLine: Color.black.opacity(0.08),
        onlineStrip: Color(red: 0.788, green: 0.635, blue: 0.153),
        subjectColors: [
            Color(red: 0.478, green: 0.067, blue: 0.157),
            Color(red: 0.694, green: 0.243, blue: 0.204),
            Color(red: 0.639, green: 0.451, blue: 0.078),
            Color(red: 0.361, green: 0.192, blue: 0.373),
            Color(red: 0.180, green: 0.353, blue: 0.310),
            Color(red: 0.247, green: 0.318, blue: 0.478),
        ]
    )

    /// Astra moon: emerald on deep navy.
    static let astraMoon = Palette(
        accent: Color(red: 0.063, green: 0.725, blue: 0.506),
        secondary: Color(red: 0.043, green: 0.067, blue: 0.125),
        canvasTop: Color(red: 0.055, green: 0.082, blue: 0.145),
        canvasBottom: Color(red: 0.024, green: 0.047, blue: 0.094),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 0.925, green: 0.616, blue: 0.243),
        subjectColors: [
            Color(red: 0.063, green: 0.725, blue: 0.506),
            Color(red: 0.024, green: 0.588, blue: 0.612),
            Color(red: 0.318, green: 0.639, blue: 0.925),
            Color(red: 0.545, green: 0.451, blue: 0.925),
            Color(red: 0.925, green: 0.616, blue: 0.243),
            Color(red: 0.914, green: 0.412, blue: 0.514),
        ]
    )
}

/// What the user picked in Settings. `auto` is the app's original behavior —
/// follow the system and swap palettes with it.
enum ThemeChoice: String, CaseIterable, Codable, Identifiable {
    case auto
    case pupMaroon
    case astraMoon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Match System"
        case .pupMaroon: "PUP Maroon"
        case .astraMoon: "Astra Moon"
        }
    }

    func palette(for systemScheme: ColorScheme) -> Palette {
        switch self {
        case .auto: systemScheme == .dark ? .astraMoon : .pupMaroon
        case .pupMaroon: .pupMaroon
        case .astraMoon: .astraMoon
        }
    }

    /// Forces native controls (fields, pickers, popovers) to match the chosen
    /// palette. Without this, picking the dark theme on a light Mac leaves
    /// every system control bright.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .pupMaroon: .light
        case .astraMoon: .dark
        }
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.pupMaroon
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Motion

/// The app's animation vocabulary, in one place so timings stay related to
/// each other rather than being invented per call site.
///
/// Every one takes `reduced` from `\.accessibilityReduceMotion` and returns
/// `nil` when it's on — a `nil` animation is SwiftUI's "apply instantly",
/// which is exactly what Reduce Motion asks for.
enum Motion {
    /// Blocks arriving, week changes — quick and settled, no overshoot to
    /// distract from the schedule itself.
    static func arrival(reduced: Bool) -> Animation? {
        reduced ? nil : .snappy(duration: 0.28)
    }

    /// Pointer feedback. Short enough to feel attached to the cursor.
    static func hover(reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: 0.12)
    }

    /// The now-line stepping a minute, and palette changes: slow and
    /// continuous, because both are ambient rather than responses to input.
    static func drift(reduced: Bool) -> Animation? {
        reduced ? nil : .smooth(duration: 0.45)
    }

    /// Blocks land in reading order instead of all at once. Capped so a busy
    /// day doesn't finish arriving noticeably later than a quiet one.
    static func stagger(_ index: Int, reduced: Bool) -> Double {
        reduced ? 0 : min(Double(index) * 0.025, 0.3)
    }

    /// The selection ring appearing. Faster than `hover` so a click feels
    /// acknowledged rather than animated at.
    static func selection(reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: 0.1)
    }

    /// A draft block following a drag. Springy enough that snapping between
    /// quarter hours reads as a snap rather than a stutter.
    static func drag(reduced: Bool) -> Animation? {
        reduced ? nil : .interactiveSpring(duration: 0.18, extraBounce: 0.1)
    }
}

// MARK: - Type scale

/// Fonts don't vary by theme, so they stay static.
enum Theme {
    /// Three faces, three jobs. New York (`.serif`) makes the course code the
    /// anchor of a block instead of another bolded caption; SF Mono keeps the
    /// time column from reshuffling its width between `9AM` and `12PM`.
    enum Typo {
        static let screenTitle = Font.system(.title2, design: .serif).weight(.semibold)

        static let dayName = Font.system(.caption, design: .default).weight(.semibold)
        static let gutter = Font.system(.caption2, design: .monospaced)

        static let blockCode = Font.system(.subheadline, design: .serif).weight(.semibold)
        static let blockTime = Font.system(size: 10, design: .monospaced)

        static let detailTitle = Font.system(.title3, design: .serif).weight(.semibold)
        static let detailBody = Font.system(.callout)
        static let detailMeta = Font.system(.caption, design: .monospaced)

        static let nowClock = Font.system(.caption2, design: .monospaced).weight(.semibold)
        static let footer = Font.system(.caption)
    }
}

// MARK: - Hex round-trip

/// Only needed because a user-picked color has to survive in `UserDefaults`,
/// which can't store a `Color`.
extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `nil` for colors with no sRGB representation (system dynamic colors) —
    /// none of which the color picker can produce, but don't crash if one does.
    var hex: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }
}
