import AppKit
import SwiftUI

/// What the user picked in Settings › Appearance › Font. `.system` is the
/// original, unbundled look — every other case names a family shipped under
/// `Resources/Fonts/` (Google Fonts, OFL-licensed; each family's `OFL.txt`
/// travels with it).
enum FontChoice: String, CaseIterable, Codable, Identifiable {
    case system
    case inter
    case poppins
    case montserrat
    case spaceGrotesk
    case ibmPlexSans
    case playfairDisplay
    case lora
    case ebGaramond
    case jetBrainsMono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .inter: "Inter"
        case .poppins: "Poppins"
        case .montserrat: "Montserrat"
        case .spaceGrotesk: "Space Grotesk"
        case .ibmPlexSans: "IBM Plex Sans"
        case .playfairDisplay: "Playfair Display"
        case .lora: "Lora"
        case .ebGaramond: "EB Garamond"
        case .jetBrainsMono: "JetBrains Mono"
        }
    }

    /// PostScript family name to hand `Font.custom`, or `nil` to fall back to
    /// the system font. These are the *variable* font's family name for every
    /// case but Poppins (shipped as static weight files upstream) — SwiftUI
    /// resolves `.weight(_:)` against a variable font's registered instances,
    /// so one file still serves regular/semibold/bold.
    var familyName: String? {
        switch self {
        case .system: nil
        case .inter: "Inter"
        case .poppins: "Poppins"
        case .montserrat: "Montserrat"
        case .spaceGrotesk: "Space Grotesk"
        case .ibmPlexSans: "IBM Plex Sans"
        case .playfairDisplay: "Playfair Display"
        case .lora: "Lora"
        case .ebGaramond: "EB Garamond"
        case .jetBrainsMono: "JetBrains Mono"
        }
    }
}

/// Registers every bundled font once, at launch. Programmatic registration
/// (rather than `ATSApplicationFontsPath` in Info.plist) because `swift run`
/// and `swift test` don't produce the app bundle `make_mac_app.sh` does — this
/// path works the same in all three.
enum FontLibrary {
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        guard let fontsDir = Bundle.module.url(forResource: "Fonts", withExtension: nil) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: fontsDir, includingPropertiesForKeys: nil
        )) ?? []

        for familyDir in files {
            let ttfs = (try? FileManager.default.contentsOfDirectory(
                at: familyDir, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension.lowercased() == "ttf" } ?? []
            for url in ttfs {
                // A font already registered (a second launch, or a name clash
                // with a system font) is not an error — just skip it.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
