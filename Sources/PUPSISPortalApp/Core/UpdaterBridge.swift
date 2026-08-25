import Sparkle

/// Sparkle's `SPUUpdaterDelegate` is an `@objc` protocol, so it needs an
/// `NSObject`. Kept as a small shim rather than reparenting `AppState` onto
/// `NSObject` — four views already observe `AppState` as a plain
/// `ObservableObject`, and that identity shouldn't change for this.
///
/// Sparkle itself owns checking, downloading, verifying, and installing —
/// this only mirrors "did it find something newer" into a `@Published`
/// value the footer badge and Settings › About can read.
final class UpdaterBridge: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// The newer version Sparkle found, or nil when up to date (or not
    /// checked yet). Only ever set from these two delegate callbacks.
    @Published var availableVersion: String?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.availableVersion = item.displayVersionString }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }
}
