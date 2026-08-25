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
    /// A dark hero-panel fill, for full-bleed surfaces like the login screen's
    /// welcome side — deliberately its own token rather than derived from
    /// `canvasBottom` with opacity math, so each theme can commit to an actual
    /// color instead of an approximation.
    let panel: Color
    /// Text/marks legible on `panel`.
    let onPanel: Color

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
        ],
        panel: Color(red: 0.078, green: 0.024, blue: 0.031),
        onPanel: Color(red: 0.988, green: 0.984, blue: 0.980)
    )

    /// Ivory: ink navy on warm cream paper. An editorial light theme, quieter
    /// than PUP Maroon — earthy jewel subjects rather than the maroon-and-gold.
    static let ivory = Palette(
        accent: Color(red: 0.204, green: 0.235, blue: 0.318),
        secondary: Color(red: 0.620, green: 0.553, blue: 0.400),
        canvasTop: Color(red: 0.992, green: 0.984, blue: 0.965),
        canvasBottom: Color(red: 0.965, green: 0.949, blue: 0.918),
        gridLine: Color.black.opacity(0.07),
        onlineStrip: Color(red: 0.788, green: 0.475, blue: 0.325),
        subjectColors: [
            Color(red: 0.204, green: 0.235, blue: 0.318),
            Color(red: 0.706, green: 0.376, blue: 0.278),
            Color(red: 0.639, green: 0.494, blue: 0.196),
            Color(red: 0.451, green: 0.310, blue: 0.416),
            Color(red: 0.325, green: 0.427, blue: 0.310),
            Color(red: 0.243, green: 0.451, blue: 0.467),
        ],
        panel: Color(red: 0.129, green: 0.129, blue: 0.145),
        onPanel: Color(red: 0.992, green: 0.984, blue: 0.965)
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
        ],
        panel: Color(red: 0.024, green: 0.039, blue: 0.075),
        onPanel: Color(red: 0.945, green: 0.965, blue: 0.980)
    )

    /// Sakura: hot pink on warm blush paper.
    static let sakura = Palette(
        accent: Color(red: 0.878, green: 0.255, blue: 0.494),
        secondary: Color(red: 0.788, green: 0.561, blue: 0.651),
        canvasTop: Color(red: 1.000, green: 0.969, blue: 0.980),
        canvasBottom: Color(red: 0.988, green: 0.914, blue: 0.941),
        gridLine: Color.black.opacity(0.06),
        onlineStrip: Color(red: 1.000, green: 0.561, blue: 0.639),
        subjectColors: [
            Color(red: 0.878, green: 0.255, blue: 0.494),
            Color(red: 0.945, green: 0.427, blue: 0.400),
            Color(red: 0.545, green: 0.318, blue: 0.635),
            Color(red: 0.788, green: 0.635, blue: 0.153),
            Color(red: 0.216, green: 0.545, blue: 0.522),
            Color(red: 0.204, green: 0.235, blue: 0.318),
        ],
        panel: Color(red: 0.129, green: 0.031, blue: 0.086),
        onPanel: Color(red: 1.000, green: 0.969, blue: 0.980)
    )

    /// Monochrome: black and gray on white, clean — no color at all beyond
    /// lightness. Subjects read apart by shade, not hue.
    static let monochrome = Palette(
        accent: Color(red: 0.067, green: 0.067, blue: 0.067),
        secondary: Color(red: 0.502, green: 0.502, blue: 0.502),
        canvasTop: Color(red: 1.000, green: 1.000, blue: 1.000),
        canvasBottom: Color(red: 0.949, green: 0.949, blue: 0.949),
        gridLine: Color.black.opacity(0.08),
        onlineStrip: Color(red: 0.251, green: 0.251, blue: 0.251),
        subjectColors: [
            Color(red: 0.102, green: 0.102, blue: 0.102),
            Color(red: 0.239, green: 0.239, blue: 0.239),
            Color(red: 0.361, green: 0.361, blue: 0.361),
            Color(red: 0.478, green: 0.478, blue: 0.478),
            Color(red: 0.600, green: 0.600, blue: 0.600),
            Color(red: 0.722, green: 0.722, blue: 0.722),
        ],
        panel: Color(red: 0.067, green: 0.067, blue: 0.067),
        onPanel: Color(red: 1.000, green: 1.000, blue: 1.000)
    )

    /// Matrix: phosphor green terminal on black.
    static let matrix = Palette(
        accent: Color(red: 0.000, green: 1.000, blue: 0.255),
        secondary: Color(red: 0.000, green: 0.561, blue: 0.067),
        canvasTop: Color(red: 0.051, green: 0.059, blue: 0.051),
        canvasBottom: Color(red: 0.000, green: 0.000, blue: 0.000),
        gridLine: Color.white.opacity(0.08),
        onlineStrip: Color(red: 1.000, green: 0.690, blue: 0.000),
        subjectColors: [
            Color(red: 0.000, green: 1.000, blue: 0.255),
            Color(red: 0.000, green: 0.898, blue: 0.831),
            Color(red: 1.000, green: 0.690, blue: 0.000),
            Color(red: 0.000, green: 0.561, blue: 0.067),
            Color(red: 0.827, green: 0.827, blue: 0.827),
            Color(red: 0.157, green: 0.678, blue: 0.522),
        ],
        panel: Color(red: 0.000, green: 0.000, blue: 0.000),
        onPanel: Color(red: 0.000, green: 1.000, blue: 0.255)
    )
}

/// What the user picked in Settings. `auto` is the app's original behavior —
/// follow the system and swap palettes with it.
enum ThemeChoice: String, CaseIterable, Codable, Identifiable {
    case auto
    case pupMaroon
    case ivory
    case astraMoon
    case sakura
    case monochrome
    case matrix

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Match System"
        case .pupMaroon: "PUP Maroon"
        case .ivory: "Ivory"
        case .astraMoon: "Astra Moon"
        case .sakura: "Sakura"
        case .monochrome: "Monochrome"
        case .matrix: "Matrix"
        }
    }

    func palette(for systemScheme: ColorScheme) -> Palette {
        switch self {
        case .auto: systemScheme == .dark ? .astraMoon : .pupMaroon
        case .pupMaroon: .pupMaroon
        case .ivory: .ivory
        case .astraMoon: .astraMoon
        case .sakura: .sakura
        case .monochrome: .monochrome
        case .matrix: .matrix
        }
    }

    /// Forces native controls (fields, pickers, popovers) to match the chosen
    /// palette. Without this, picking the dark theme on a light Mac leaves
    /// every system control bright.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .pupMaroon: .light
        case .ivory: .light
        case .astraMoon: .dark
        case .sakura: .light
        case .monochrome: .light
        case .matrix: .dark
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

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = Typography(.system)
}

extension EnvironmentValues {
    var typography: Typography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
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

    /// The nav island gliding centre↔top and morphing collapsed↔expanded. A
    /// gentle spring so the flight reads as one continuous move, not a snap.
    static func island(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }
}

// MARK: - Chrome

enum Theme {
    /// The floating top chrome — the dither band, the window-drag surface, and
    /// the destination's own top inset all key off this one value, rather than
    /// three matching-by-coincidence literals.
    enum Chrome {
        /// Height of the strip the nav island floats in.
        static let topStrip: CGFloat = 40
        /// Slightly inside the NSWindow's own rounded corner, so the chrome
        /// band's dither cells are never sliced mid-square by the window mask.
        static let windowRadius: CGFloat = 14
    }
}

// MARK: - Type scale

/// The app's type scale, built from a `FontChoice`. A value rather than
/// statics — same reasoning as `Palette` above a `static let` can't re-render
/// when the user changes their pick in Settings. Every entry keeps the same
/// *size and role* `Theme.Typo` always had; only the family changes.
///
/// `.system` reproduces the original hardcoded scale exactly: New York
/// (`.serif`) makes the course code the anchor of a block instead of another
/// bolded caption, SF Mono keeps the time column from reshuffling its width
/// between `9AM` and `12PM`.
struct Typography: Equatable {
    let choice: FontChoice

    init(_ choice: FontChoice) {
        self.choice = choice
    }

    // `weight` is optional and only ever applied when given: the original
    // hardcoded scale left five entries at the system default rather than
    // spelling out `.weight(.regular)`, and `Font` compares its *build*, not
    // its rendered appearance, so `.weight(.regular)` is not `==` to the same
    // font left alone. Matching that shape exactly is what lets `.system`
    // still equal the original literals.
    private func font(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight? = nil) -> Font {
        let base = choice.familyName.map { Font.custom($0, size: Theme.pointSize(for: style)) }
            ?? Font.system(style, design: design)
        return weight.map(base.weight) ?? base
    }

    private func font(size: CGFloat, design: Font.Design = .default, weight: Font.Weight? = nil) -> Font {
        let base = choice.familyName.map { Font.custom($0, size: size) }
            ?? Font.system(size: size, design: design)
        return weight.map(base.weight) ?? base
    }

    /// The home wordmark. `.largeTitle` — matches the size the wordmark always
    /// rendered at (previously an inline `.system(.largeTitle, …)` literal),
    /// so picking `.system` here reproduces that exactly.
    var hero: Font { font(.largeTitle, design: .serif, weight: .semibold) }

    /// The login screen's oversized welcome line — bigger than `hero`, the
    /// one place in the app that goes past a title.
    var loginHeadline: Font { font(size: 40, design: .serif, weight: .light) }

    var screenTitle: Font { font(.title2, design: .serif, weight: .semibold) }

    var dayName: Font { font(.caption, weight: .semibold) }
    var gutter: Font { font(.caption2, design: .monospaced) }

    var blockCode: Font { font(.subheadline, design: .serif, weight: .semibold) }
    var blockTime: Font { font(size: 10, design: .monospaced) }

    var detailTitle: Font { font(.title3, design: .serif, weight: .semibold) }
    var detailBody: Font { font(.callout) }
    var detailMeta: Font { font(.caption, design: .monospaced) }

    var nowClock: Font { font(.caption2, design: .monospaced, weight: .semibold) }
    var footer: Font { font(.caption) }
}

extension Theme {
    /// `Font.custom` needs a point size, not a `TextStyle` — this is the fixed
    /// mapping macOS uses for `.system(_:)` at Dynamic Type's default size, so
    /// a custom family lines up with what the system design would have been.
    fileprivate static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote: 10
        case .caption: 10
        case .caption2: 10
        default: 13
        }
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
