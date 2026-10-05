//! The glance outside the app: the Swift side writes the next class where
//! the widget extension reads it, refreshes the widget, and runs the Live
//! Activity; the Kotlin side draws the home-screen widget and a Live Update
//! (the status-bar chip that stands in for the Dynamic Island). The web view calls `plugin:glance|update` directly; there is
//! no Rust command, and on other platforms the plugin does nothing.

use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_glance);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("glance")
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            {
                use tauri::Manager;
                _app.manage(_api.register_ios_plugin(init_plugin_glance)?);
            }
            #[cfg(target_os = "android")]
            {
                use tauri::Manager;
                _app.manage(_api.register_android_plugin("ph.intportal.glance", "GlancePlugin")?);
            }
            Ok(())
        })
        .build()
}
