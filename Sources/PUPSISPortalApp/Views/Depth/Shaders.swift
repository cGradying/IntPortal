import SwiftUI

/// The app's own Metal shaders (Resources/Shaders). Looked up by path, never
/// through `Bundle.module`, whose generated accessor crashes the packaged app
/// when its bundle isn't where it expects (see FontLibrary). `nil` means
/// Metal is unavailable and every effect draws its Canvas fallback instead.
enum Shaders {
    /// The packaged app's copy (make_mac_app.sh) or, for `swift run` and
    /// tests, SwiftPM's compiled library inside `bundle`.
    static func load(from bundle: Bundle = .main) -> ShaderLibrary? {
        guard !ProcessInfo.processInfo.arguments.contains("-IntPortalNoMetal") else { return nil }
        let url = bundle.url(forResource: "PortalShaders", withExtension: "metallib")
            ?? bundle.url(forResource: "default", withExtension: "metallib")
        return url.map(ShaderLibrary.init(url:))
    }

    @MainActor static var library = load()
}
