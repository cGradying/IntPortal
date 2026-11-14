//! The commands the UI invokes, one file per area.
//!
//! A command that isn't `async fn` is marked `#[tauri::command(async)]`: Tauri runs a plain
//! command on the main thread, and none of these should hold up a frame for the store or the keychain.

pub mod account;
pub mod backup;
pub mod coach;
pub mod deadlines;
pub mod mabini;
pub mod notes;
pub mod schedule;
pub mod study;
