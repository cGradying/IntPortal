//! One photo from the camera or the library: Vision (iOS) or ML Kit (Android)
//! reads its text and QR codes on the phone, and it is kept only when the
//! caller names a folder. The web view calls `plugin:camera|capture` directly;
//! there is no Rust command, and on other platforms the plugin does nothing.

use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_camera);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("camera")
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            {
                use tauri::Manager;
                _app.manage(_api.register_ios_plugin(init_plugin_camera)?);
            }
            #[cfg(target_os = "android")]
            {
                use tauri::Manager;
                _app.manage(_api.register_android_plugin("ph.intportal.camera", "CameraPlugin")?);
            }
            Ok(())
        })
        .build()
}
