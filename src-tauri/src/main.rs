// IntPortal on Mac, Windows and Linux (spec 053). The library's crate types
// leave out rlib so mobile release builds keep link-time optimisation (#291),
// so this binary compiles lib.rs as its own source instead of linking it.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

include!("lib.rs");

fn main() {
    run();
}
