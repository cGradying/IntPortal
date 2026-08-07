import ServiceManagement

/// Registers the app to launch at login, so its reminders keep firing when it's
/// fully quit — not just window-closed.
///
/// `SMAppService.mainApp` registers the main bundle itself; no bundled helper
/// and no Info.plist key, which is why `Scripts/make_mac_app.sh` needs no
/// change. It does require a signed bundle in a stable location — the app's
/// signing identity (see the repo's signing script) is what makes registration
/// stick across rebuilds.
///
/// The OS is the source of truth: read `isEnabled` rather than caching a bool,
/// so the toggle can't drift out of step with System Settings > Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Best-effort: on failure the status simply stays what it was, and the
    /// caller re-reads `isEnabled` so the toggle reflects reality.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail (unsigned build, bad location). Nothing to
            // recover — the toggle re-reads the real status.
        }
    }
}
