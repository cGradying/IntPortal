// The app's Rust calls the native side through `Download`; the web view calls nothing here.
const COMMANDS: &[&str] = &[];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).android_path("android").ios_path("ios").build();
}
