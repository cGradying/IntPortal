//! Spike: Apple's on-device Foundation Models as an optional chat provider.
//! The Swift side does everything; the web view calls
//! `plugin:foundation|availability`, `|generate` (streams through a Channel)
//! and `|cancel` directly. There is no Rust command and no Android half.

use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_foundation);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("foundation")
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            {
                use tauri::Manager;
                _app.manage(_api.register_ios_plugin(init_plugin_foundation)?);
            }
            Ok(())
        })
        .build()
}
