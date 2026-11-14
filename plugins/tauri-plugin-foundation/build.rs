const COMMANDS: &[&str] = &["availability", "generate", "cancel"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
}
