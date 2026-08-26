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
/// and `swift test` don't produce the app bundle `make_mac_app.sh` does.
///
/// Reads through `Bundle.main`, same as `WebNoteEditor`'s
/// `notes-editor.bundle.js` lookup — **not** SwiftPM's `Bundle.module`.
/// Confirmed the hard way that `Bundle.module`'s generated accessor checks
/// `Bundle.main.bundleURL` (the packaged `.app`'s own root, not
/// `Contents/Resources`) for a `PUPSISPortal_PUPSISPortal.bundle` folder
/// `make_mac_app.sh` never creates there — and a `fatalError` inside that
/// accessor's lazy static init can't be caught, so it crashed every real
/// launch while `swift build`/`swift test` never surfaced it at all, since a
/// dev build resolves that same accessor differently. `Bundle.main` finds
/// `Contents/Resources/Fonts` in the real app, and simply returns nil here
/// (graceful no-op, not a crash) under `swift run`/`swift test`, where
/// nothing copies that folder in.
enum FontLibrary {
    private static var didRegister = false

    /// `bundle` defaults to `.main` for real use (the packaged `.app`'s
    /// `Contents/Resources`) — injectable so `swift test` can pass `.module`
    /// instead, which resolves correctly in that environment (unlike
    /// `.main`, which is the xctest runner there, not this package) and lets
    /// `PreferencesTests.testEveryBundledFamilyIsRegistered` still verify
    /// real `CTFontManager` registration rather than trusting it blindly.
    static func registerBundledFonts(in bundle: Bundle = .main) {
        guard !didRegister else { return }
        didRegister = true

        guard let fontsDir = bundle.url(forResource: "Fonts", withExtension: nil) else { return }
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
