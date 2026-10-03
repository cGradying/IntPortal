//! The phone's own calendar, through EventKit: the student's events (so the
//! coach counts them as busy) and an IntPortal calendar the app owns for
//! their classes. The web view calls `plugin:calendar|…` directly; there is
//! no Rust command, and on other platforms the plugin does nothing.

use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_calendar);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("calendar")
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            {
                use tauri::Manager;
                _app.manage(_api.register_ios_plugin(init_plugin_calendar)?);
            }
            Ok(())
        })
        .build()
}
