import SwiftUI
import AppKit

/// Light mode: PUP maroon/gold. Dark mode: astra moon emerald/navy.
enum Theme {
    static let accent = dynamic(
        light: NSColor(red: 0.478, green: 0.067, blue: 0.157, alpha: 1), // PUP maroon
        dark: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1)   // astra moon emerald
    )

    static let secondary = dynamic(
        light: NSColor(red: 0.788, green: 0.635, blue: 0.153, alpha: 1), // PUP gold
        dark: NSColor(red: 0.043, green: 0.067, blue: 0.125, alpha: 1)   // astra moon navy
    )

    static let canvas = dynamic(
        light: NSColor(red: 0.976, green: 0.973, blue: 0.969, alpha: 1),
        dark: NSColor(red: 0.043, green: 0.067, blue: 0.125, alpha: 1)
    )

    static let gridLine = dynamic(
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.10)
    )

    /// Per-subject block colors. Light set leans into PUP maroon/gold, dark
    /// set into the astra moon emerald/teal range.
    private static let palette: [(NSColor, NSColor)] = [
        (NSColor(red: 0.478, green: 0.067, blue: 0.157, alpha: 1), NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1)),
        (NSColor(red: 0.694, green: 0.243, blue: 0.204, alpha: 1), NSColor(red: 0.024, green: 0.588, blue: 0.612, alpha: 1)),
        (NSColor(red: 0.639, green: 0.451, blue: 0.078, alpha: 1), NSColor(red: 0.318, green: 0.639, blue: 0.925, alpha: 1)),
        (NSColor(red: 0.361, green: 0.192, blue: 0.373, alpha: 1), NSColor(red: 0.545, green: 0.451, blue: 0.925, alpha: 1)),
        (NSColor(red: 0.180, green: 0.353, blue: 0.310, alpha: 1), NSColor(red: 0.925, green: 0.616, blue: 0.243, alpha: 1)),
        (NSColor(red: 0.247, green: 0.318, blue: 0.478, alpha: 1), NSColor(red: 0.914, green: 0.412, blue: 0.514, alpha: 1)),
    ]

    /// Stable across launches — `Hashable` seeds randomly per process, which
    /// would repaint every subject a different color each run.
    static func color(for subjectCode: String) -> Color {
        let seed = subjectCode.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let (light, dark) = palette[seed % palette.count]
        return dynamic(light: light, dark: dark)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
