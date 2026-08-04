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

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
