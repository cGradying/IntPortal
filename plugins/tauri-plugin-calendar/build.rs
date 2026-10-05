const COMMANDS: &[&str] = &["status", "request", "events", "sync_classes"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).android_path("android").ios_path("ios").build();
}
