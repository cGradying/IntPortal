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
    /// The Registrar role set from DESIGN.md. Rooms that predate it borrow
    /// Registrar's until S1 either retunes or removes them.
    var roles: Roles = .registrar

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
    /// DESIGN.md's roles. The menu field is the one committed color, action is
    /// the only interactive hue, gold marks the present and stamps.
    struct Roles: Equatable {
        let menuField: Color
        let menuFieldDeep: Color
        let menuFieldHover: Color
        let onMenu: Color
        let onMenu2: Color
        let action: Color
        let actionHover: Color
        let actionSoft: Color
        let actionInk: Color
        /// Text on an action fill.
        let onAction: Color
        let gold: Color
        let goldInk: Color
        let goldSoft: Color
        let ground: Color
        let sheet: Color
        let sunk: Color
        let line: Color
        let line2: Color
        let ink: Color
        let ink2: Color
        let ink3: Color
        let good: Color
        let bad: Color

        static let registrar = Roles(
            menuField: Color(rgb: 0x6D0E1F), menuFieldDeep: Color(rgb: 0x560A19), menuFieldHover: Color(rgb: 0x7E1A2C),
            onMenu: Color(rgb: 0xF7ECEC), onMenu2: Color(rgb: 0xDDB9BE),
            action: Color(rgb: 0x1B5DB8), actionHover: Color(rgb: 0x154C98), actionSoft: Color(rgb: 0xE3ECF9), actionInk: Color(rgb: 0x1B4F99), onAction: Color(rgb: 0xFFFFFF),
            gold: Color(rgb: 0xC9A227), goldInk: Color(rgb: 0x765806), goldSoft: Color(rgb: 0xF4E8C2),
            ground: Color(rgb: 0xF4F2EF), sheet: Color(rgb: 0xFFFFFF), sunk: Color(rgb: 0xF7F5F2),
            line: Color(rgb: 0xE2DDD6), line2: Color(rgb: 0xCBC3B9),
            ink: Color(rgb: 0x1C1517), ink2: Color(rgb: 0x554C4F), ink3: Color(rgb: 0x766C6F),
            good: Color(rgb: 0x1E7249), bad: Color(rgb: 0xB42318)
        )

        /// Same roles retuned for dark, never inverted.
        static let registrarNight = Roles(
            menuField: Color(rgb: 0x35060F), menuFieldDeep: Color(rgb: 0x4A0C19), menuFieldHover: Color(rgb: 0x5C1424),
            onMenu: Color(rgb: 0xF4E6E8), onMenu2: Color(rgb: 0xC99BA3),
            action: Color(rgb: 0x5B93F0), actionHover: Color(rgb: 0x7BA8F3), actionSoft: Color(rgb: 0x1A2640), actionInk: Color(rgb: 0x8DB4F5), onAction: Color(rgb: 0x0A1428),
            gold: Color(rgb: 0xDDB64E), goldInk: Color(rgb: 0xE6C66A), goldSoft: Color(rgb: 0x3A3016),
            ground: Color(rgb: 0x141112), sheet: Color(rgb: 0x1C1819), sunk: Color(rgb: 0x171415),
            line: Color(rgb: 0x2D2728), line2: Color(rgb: 0x433A3C),
            ink: Color(rgb: 0xF2ECE9), ink2: Color(rgb: 0xBCB2B4), ink3: Color(rgb: 0x958A8D),
            good: Color(rgb: 0x5CC08C), bad: Color(rgb: 0xF07A6E)
        )
    }

    /// The Registrar world, light. Legacy fields map onto the roles so views
    /// not yet moved to `roles` still read sensibly.
    static let registrar = Palette(
        accent: Color(rgb: 0x6D0E1F),
        secondary: Color(rgb: 0xC9A227),
        canvasTop: Color(rgb: 0xF4F2EF),
        canvasBottom: Color(rgb: 0xF4F2EF),
        gridLine: Color(rgb: 0xE2DDD6),
        onlineStrip: Color(rgb: 0x1B5DB8),
        subjectColors: [0x7A1128, 0xB13E34, 0x8F6410, 0x5C315F, 0x2E5A4F, 0x3F517A].map { Color(rgb: $0) },
        panel: Color(rgb: 0x07050A),
        onPanel: Color(rgb: 0xF4E8D6),
        roles: .registrar
    )

    /// The Registrar world, dark.
    static let registrarNight = Palette(
        accent: Color(rgb: 0xD66A7E),
        secondary: Color(rgb: 0xDDB64E),
        canvasTop: Color(rgb: 0x141112),
        canvasBottom: Color(rgb: 0x141112),
        gridLine: Color(rgb: 0x2D2728),
        onlineStrip: Color(rgb: 0x5B93F0),
        subjectColors: [0xD66A7E, 0xE07D70, 0xD5A544, 0xB083B3, 0x62AE94, 0x8398CD].map { Color(rgb: $0) },
        panel: Color(rgb: 0x07050A),
        onPanel: Color(rgb: 0xF4E8D6),
        roles: .registrarNight
    )

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

    // MARK: Famous editor themes

    /// Dracula.
    static let dracula = Palette(
        accent: Color(red: 0.741, green: 0.576, blue: 0.976),
        secondary: Color(red: 0.384, green: 0.447, blue: 0.643),
        canvasTop: Color(red: 0.157, green: 0.165, blue: 0.212),
        canvasBottom: Color(red: 0.114, green: 0.121, blue: 0.157),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 1.000, green: 0.475, blue: 0.776),
        subjectColors: [
            Color(red: 0.741, green: 0.576, blue: 0.976),
            Color(red: 1.000, green: 0.475, blue: 0.776),
            Color(red: 0.545, green: 0.914, blue: 0.992),
            Color(red: 0.314, green: 0.980, blue: 0.482),
            Color(red: 1.000, green: 0.722, blue: 0.424),
            Color(red: 1.000, green: 0.333, blue: 0.333),
        ],
        panel: Color(red: 0.078, green: 0.082, blue: 0.106),
        onPanel: Color(red: 0.973, green: 0.973, blue: 0.949)
    )

    /// Nord.
    static let nord = Palette(
        accent: Color(red: 0.533, green: 0.753, blue: 0.816),
        secondary: Color(red: 0.463, green: 0.514, blue: 0.635),
        canvasTop: Color(red: 0.180, green: 0.204, blue: 0.251),
        canvasBottom: Color(red: 0.145, green: 0.161, blue: 0.200),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 0.922, green: 0.796, blue: 0.545),
        subjectColors: [
            Color(red: 0.533, green: 0.753, blue: 0.816),
            Color(red: 0.506, green: 0.631, blue: 0.757),
            Color(red: 0.365, green: 0.506, blue: 0.675),
            Color(red: 0.639, green: 0.745, blue: 0.549),
            Color(red: 0.922, green: 0.796, blue: 0.545),
            Color(red: 0.706, green: 0.557, blue: 0.678),
        ],
        panel: Color(red: 0.106, green: 0.118, blue: 0.145),
        onPanel: Color(red: 0.925, green: 0.937, blue: 0.957)
    )

    /// Gruvbox (dark, hard contrast).
    static let gruvbox = Palette(
        accent: Color(red: 0.980, green: 0.741, blue: 0.184),
        secondary: Color(red: 0.573, green: 0.514, blue: 0.455),
        canvasTop: Color(red: 0.157, green: 0.157, blue: 0.157),
        canvasBottom: Color(red: 0.114, green: 0.125, blue: 0.129),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 0.984, green: 0.286, blue: 0.204),
        subjectColors: [
            Color(red: 0.980, green: 0.741, blue: 0.184),
            Color(red: 0.722, green: 0.733, blue: 0.149),
            Color(red: 0.514, green: 0.647, blue: 0.596),
            Color(red: 0.827, green: 0.525, blue: 0.608),
            Color(red: 0.984, green: 0.286, blue: 0.204),
            Color(red: 0.686, green: 0.502, blue: 0.792),
        ],
        panel: Color(red: 0.098, green: 0.098, blue: 0.098),
        onPanel: Color(red: 0.922, green: 0.859, blue: 0.698)
    )

    /// Solarized Dark.
    static let solarizedDark = Palette(
        accent: Color(red: 0.149, green: 0.545, blue: 0.824),
        secondary: Color(red: 0.396, green: 0.482, blue: 0.514),
        canvasTop: Color(red: 0.027, green: 0.212, blue: 0.259),
        canvasBottom: Color(red: 0.000, green: 0.169, blue: 0.212),
        gridLine: Color.white.opacity(0.09),
        onlineStrip: Color(red: 0.796, green: 0.294, blue: 0.086),
        subjectColors: [
            Color(red: 0.149, green: 0.545, blue: 0.824),
            Color(red: 0.518, green: 0.600, blue: 0.000),
            Color(red: 0.835, green: 0.212, blue: 0.510),
            Color(red: 0.710, green: 0.537, blue: 0.000),
            Color(red: 0.165, green: 0.631, blue: 0.596),
            Color(red: 0.427, green: 0.443, blue: 0.769),
        ],
        panel: Color(red: 0.020, green: 0.161, blue: 0.196),
        onPanel: Color(red: 0.933, green: 0.910, blue: 0.835)
    )

    /// Solarized Light.
    static let solarizedLight = Palette(
        accent: Color(red: 0.149, green: 0.545, blue: 0.824),
        secondary: Color(red: 0.576, green: 0.631, blue: 0.631),
        canvasTop: Color(red: 0.992, green: 0.965, blue: 0.890),
        canvasBottom: Color(red: 0.933, green: 0.910, blue: 0.835),
        gridLine: Color.black.opacity(0.07),
        onlineStrip: Color(red: 0.796, green: 0.294, blue: 0.086),
        subjectColors: [
            Color(red: 0.149, green: 0.545, blue: 0.824),
            Color(red: 0.518, green: 0.600, blue: 0.000),
            Color(red: 0.835, green: 0.212, blue: 0.510),
            Color(red: 0.710, green: 0.537, blue: 0.000),
            Color(red: 0.165, green: 0.631, blue: 0.596),
            Color(red: 0.427, green: 0.443, blue: 0.769),
        ],
        panel: Color(red: 0.027, green: 0.212, blue: 0.259),
        onPanel: Color(red: 0.933, green: 0.910, blue: 0.835)
    )

    /// Tokyo Night.
    static let tokyoNight = Palette(
        accent: Color(red: 0.478, green: 0.635, blue: 0.969),
        secondary: Color(red: 0.322, green: 0.337, blue: 0.443),
        canvasTop: Color(red: 0.102, green: 0.106, blue: 0.149),
        canvasBottom: Color(red: 0.071, green: 0.075, blue: 0.106),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 0.878, green: 0.596, blue: 0.376),
        subjectColors: [
            Color(red: 0.478, green: 0.635, blue: 0.969),
            Color(red: 0.741, green: 0.573, blue: 0.976),
            Color(red: 0.416, green: 0.847, blue: 0.937),
            Color(red: 0.616, green: 0.804, blue: 0.427),
            Color(red: 0.878, green: 0.596, blue: 0.376),
            Color(red: 0.969, green: 0.463, blue: 0.557),
        ],
        panel: Color(red: 0.055, green: 0.059, blue: 0.086),
        onPanel: Color(red: 0.773, green: 0.792, blue: 0.902)
    )

    /// Catppuccin Mocha.
    static let catppuccin = Palette(
        accent: Color(red: 0.796, green: 0.651, blue: 0.969),
        secondary: Color(red: 0.541, green: 0.561, blue: 0.702),
        canvasTop: Color(red: 0.180, green: 0.184, blue: 0.251),
        canvasBottom: Color(red: 0.118, green: 0.118, blue: 0.180),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 0.980, green: 0.702, blue: 0.529),
        subjectColors: [
            Color(red: 0.796, green: 0.651, blue: 0.969),
            Color(red: 0.957, green: 0.761, blue: 0.847),
            Color(red: 0.573, green: 0.882, blue: 0.980),
            Color(red: 0.651, green: 0.890, blue: 0.631),
            Color(red: 0.980, green: 0.702, blue: 0.529),
            Color(red: 0.953, green: 0.545, blue: 0.659),
        ],
        panel: Color(red: 0.090, green: 0.094, blue: 0.145),
        onPanel: Color(red: 0.804, green: 0.839, blue: 0.957)
    )

    /// One Dark (Atom).
    static let oneDark = Palette(
        accent: Color(red: 0.380, green: 0.686, blue: 0.937),
        secondary: Color(red: 0.353, green: 0.388, blue: 0.443),
        canvasTop: Color(red: 0.173, green: 0.180, blue: 0.204),
        canvasBottom: Color(red: 0.129, green: 0.135, blue: 0.153),
        gridLine: Color.white.opacity(0.10),
        onlineStrip: Color(red: 0.820, green: 0.604, blue: 0.400),
        subjectColors: [
            Color(red: 0.380, green: 0.686, blue: 0.937),
            Color(red: 0.776, green: 0.471, blue: 0.867),
            Color(red: 0.337, green: 0.714, blue: 0.761),
            Color(red: 0.596, green: 0.765, blue: 0.475),
            Color(red: 0.820, green: 0.604, blue: 0.400),
            Color(red: 0.878, green: 0.424, blue: 0.459),
        ],
        panel: Color(red: 0.106, green: 0.110, blue: 0.125),
        onPanel: Color(red: 0.671, green: 0.698, blue: 0.749)
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
    case dracula
    case nord
    case gruvbox
    case solarizedDark
    case solarizedLight
    case tokyoNight
    case catppuccin
    case oneDark

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
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .gruvbox: "Gruvbox"
        case .solarizedDark: "Solarized Dark"
        case .solarizedLight: "Solarized Light"
        case .tokyoNight: "Tokyo Night"
        case .catppuccin: "Catppuccin Mocha"
        case .oneDark: "One Dark"
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
        case .dracula: .dracula
        case .nord: .nord
        case .gruvbox: .gruvbox
        case .solarizedDark: .solarizedDark
        case .solarizedLight: .solarizedLight
        case .tokyoNight: .tokyoNight
        case .catppuccin: .catppuccin
        case .oneDark: .oneDark
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
        case .dracula: .dark
        case .nord: .dark
        case .gruvbox: .dark
        case .solarizedDark: .dark
        case .solarizedLight: .light
        case .tokyoNight: .dark
        case .catppuccin: .dark
        case .oneDark: .dark
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

/// `Preferences.uiScale`, for the handful of views that need the raw factor
/// for their own fixed pixel geometry (a popover's width, the now-line
/// lozenge) rather than a pre-scaled font from `Typography`. Views that
/// already hold a `Preferences` reference (`WeekGrid`) just read
/// `preferences.uiScale` directly — this exists for the ones that don't.
private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var uiScale: Double {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

/// `\.accessibilityReduceMotion` has no public setter, so Settings' "Force
/// Reduce Motion" could never reach it. This is the value every view reads:
/// the system setting OR'd with the in-app one, set once at the root.
private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var reduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// Publishes `\.reduceMotion` for everything below: the system setting
    /// OR'd with `forced`.
    func reduceMotion(forced: Bool) -> some View {
        modifier(ReduceMotionRoot(forced: forced))
    }
}

private struct ReduceMotionRoot: ViewModifier {
    let forced: Bool
    @Environment(\.accessibilityReduceMotion) private var system

    func body(content: Content) -> some View {
        content.environment(\.reduceMotion, system || forced)
    }
}

// MARK: - Spacing

/// DESIGN.md's 4-point scale.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}

// MARK: - Motion

/// The app's animation vocabulary, in one place so timings stay related to
/// each other rather than being invented per call site.
///
/// Every one takes `reduced` from `\.reduceMotion` and returns
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

    // The Registrar set. Springs keep their velocity when a new input
    // retargets them mid-flight, which is the macOS 27 feel DESIGN.md asks for.

    /// A status stamp landing.
    static func thunk(reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.42)
    }

    /// A flashcard turning over.
    static func flip(reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.3, 0.7, 0.2, 1, duration: 0.55)
    }

    /// A matched pair.
    static func pop(reduced: Bool) -> Animation? {
        reduced ? nil : .snappy(duration: 0.35, extraBounce: 0.2)
    }

    /// The obsidian frame assembling on the landing.
    static func portalForm(reduced: Bool) -> Animation? {
        reduced ? nil : .linear(duration: 1.2)
    }

    /// The swirl filling the frame.
    static func ignite(reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: 0.5)
    }

    /// The dive into a portal: slow start, hard finish.
    static func warp(reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.55, 0, 1, 0.45, duration: 0.95)
    }

    /// The gold band that reveals AI text.
    static func sweep(reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.3, 0.7, 0.2, 1, duration: 1.2)
    }

    /// The hub ring stepping one portal.
    static func orbit(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.34, dampingFraction: 0.86)
    }

    /// The Schedule week turning.
    static func turn(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.42, dampingFraction: 0.9)
    }

    /// A screen change moving along the sidebar's order.
    static func depthPush(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.3, dampingFraction: 0.92)
    }

    /// The sync ring leaving the portal glyph.
    static func ripple(reduced: Bool) -> Animation? {
        reduced ? nil : .linear(duration: 0.7)
    }

    /// A deck fanning out its due cards.
    static func fan(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.4, dampingFraction: 0.8)
    }

    /// The IntAssis cube turning while the model works.
    static func think(reduced: Bool) -> Animation? {
        reduced ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false)
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
    /// `Preferences.uiScale` — multiplies every point size below, so text
    /// stays vector-crisp at every zoom level instead of being rasterized at
    /// 100% and stretched (`UIScale.swift`, deleted, used to do that with a
    /// root `.scaleEffect`). `== 1` for `.system` takes the style-based
    /// branch below so `testSystemChoiceMatchesTheOriginalScale` keeps
    /// comparing identical `Font` builds at the default zoom.
    let scale: Double

    init(_ choice: FontChoice, scale: Double = 1.0) {
        self.choice = choice
        self.scale = scale
    }

    // `weight` is optional and only ever applied when given: the original
    // hardcoded scale left five entries at the system default rather than
    // spelling out `.weight(.regular)`, and `Font` compares its *build*, not
    // its rendered appearance, so `.weight(.regular)` is not `==` to the same
    // font left alone. Matching that shape exactly is what lets `.system`
    // still equal the original literals.
    private func font(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight? = nil) -> Font {
        let base: Font
        if let family = choice.familyName {
            base = Font.custom(family, size: Theme.pointSize(for: style) * scale)
        } else if scale == 1 {
            base = Font.system(style, design: design)
        } else {
            base = Font.system(size: Theme.pointSize(for: style) * scale, design: design)
        }
        return weight.map(base.weight) ?? base
    }

    private func font(size: CGFloat, design: Font.Design = .default, weight: Font.Weight? = nil) -> Font {
        let base = choice.familyName.map { Font.custom($0, size: size * scale) }
            ?? Font.system(size: size * scale, design: design)
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

    /// Pixelify Sans, the identity face (titles, codes, numbers, buttons).
    /// Ignores `choice`: the user's font pick applies to reading text only.
    func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.custom(Self.displayFamily, size: size * scale).weight(weight)
    }

    static let displayFamily = "Pixelify Sans"

    /// Source Sans 3, the reading face (notes, descriptions, AI replies),
    /// unless the user picked another family in Settings.
    func reading(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(choice.familyName ?? "Source Sans 3", size: size * scale).weight(weight)
    }
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
    /// A design token written the way DESIGN.md writes it: `Color(rgb: 0x6D0E1F)`.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

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

    /// Black or white, whichever reads against `background` — picked by
    /// relative luminance rather than assuming every fill is dark enough for
    /// white text. Confirmed live: `.white` hardcoded on an arbitrary subject
    /// color went unreadable against Monochrome's lighter subject slot and
    /// Matrix's phosphor green — both shipped rooms where a fill can be
    /// light. `nil` background (no sRGB representation) falls back to white,
    /// matching every call site's previous behavior.
    static func legibleForeground(on background: Color) -> Color {
        guard let srgb = NSColor(background).usingColorSpace(.sRGB) else { return .white }
        // WCAG relative luminance, sRGB gamma-corrected.
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(srgb.redComponent)
            + 0.7152 * channel(srgb.greenComponent)
            + 0.0722 * channel(srgb.blueComponent)
        return luminance > 0.42 ? .black : .white
    }
}
