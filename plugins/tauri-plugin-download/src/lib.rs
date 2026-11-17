//! Model downloads that keep going when the student leaves the app (spec 021 C4, C5).
//!
//! - iOS: a background `URLSession` downloads the file while the app is suspended; the app's Rust
//!   starts it, reads its status and checks the hash when it has landed.
//! - Android: the app's own Rust download keeps running; a foreground service with a progress
//!   notification keeps the process alive meanwhile.
//! - Both: free storage where the models go, as the system counts it (iOS counts purgeable space).
//!
//! Only the app's Rust calls this, through `Download` (a newtype, so it doesn't collide with the
//! `PluginHandle` other plugins manage). Elsewhere every call is a no-op.
use serde::Deserialize;
use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_download);

/// What the iOS session knows about one file: `state` is "none", "running", "done", "paused" or
/// "failed", with `error` "offline", "nospace", "http:<code>" or the system's words.
#[derive(Debug, Default, Deserialize)]
pub struct Status {
    pub state: String,
    #[serde(default)]
    pub done: u64,
    #[serde(default)]
    pub total: u64,
    #[serde(default)]
    pub error: Option<String>,
}

#[cfg(mobile)]
#[derive(Deserialize)]
struct Bytes {
    bytes: u64,
}

pub struct Download<R: Runtime> {
    #[cfg(mobile)]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(mobile))]
    _r: std::marker::PhantomData<fn() -> R>,
}

#[cfg(mobile)]
impl<R: Runtime> Download<R> {
    fn call<T: serde::de::DeserializeOwned>(&self, cmd: &str, args: serde_json::Value) -> Result<T, String> {
        self.handle.run_mobile_plugin(cmd, args).map_err(|e| e.to_string())
    }
    fn tell(&self, cmd: &str, args: serde_json::Value) {
        let _ = self.call::<serde_json::Value>(cmd, args);
    }
}

impl<R: Runtime> Download<R> {
    /// Bytes free for the app where `path` is, or None where the platform doesn't say.
    pub fn space(&self, path: &str) -> Option<u64> {
        #[cfg(mobile)]
        return self.call::<Bytes>("space", serde_json::json!({ "path": path })).ok().map(|b| b.bytes);
        #[cfg(not(mobile))]
        {
            let _ = path;
            None
        }
    }

    /// iOS: starts (or joins, or resumes) the background download of `url` into `path`.
    pub fn start(&self, url: &str, path: &str) -> Result<(), String> {
        #[cfg(target_os = "ios")]
        return self.call::<serde_json::Value>("start", serde_json::json!({ "url": url, "path": path })).map(|_| ());
        #[cfg(not(target_os = "ios"))]
        {
            let _ = (url, path);
            Err("background downloads are iOS only".into())
        }
    }

    pub fn status(&self, path: &str) -> Status {
        #[cfg(target_os = "ios")]
        return self.call("status", serde_json::json!({ "path": path })).unwrap_or_default();
        #[cfg(not(target_os = "ios"))]
        {
            let _ = path;
            Status::default()
        }
    }

    /// iOS: stops the download and keeps what arrived for the next `start`.
    pub fn cancel(&self, path: &str) {
        #[cfg(target_os = "ios")]
        self.tell("cancel", serde_json::json!({ "path": path }));
        #[cfg(not(target_os = "ios"))]
        let _ = path;
    }

    /// Android: shows or updates the foreground notification that keeps the app alive.
    pub fn keep_alive(&self, pct: u8, text: &str) {
        #[cfg(target_os = "android")]
        self.tell("keepAlive", serde_json::json!({ "pct": pct, "text": text }));
        #[cfg(not(target_os = "android"))]
        let _ = (pct, text);
    }

    /// Android: ends the foreground service and its notification.
    pub fn release(&self) {
        #[cfg(target_os = "android")]
        self.tell("release", serde_json::json!({}));
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("download")
        .setup(|app, _api| {
            use tauri::Manager;
            #[cfg(target_os = "ios")]
            app.manage(Download { handle: _api.register_ios_plugin(init_plugin_download)? });
            #[cfg(target_os = "android")]
            app.manage(Download { handle: _api.register_android_plugin("ph.intportal.download", "DownloadPlugin")? });
            #[cfg(not(mobile))]
            app.manage(Download::<R> { _r: std::marker::PhantomData });
            Ok(())
        })
        .build()
}
