//! The login lives in the platform keychain, never in the store.
use super::{keychain, Login};

const SERVICE: &str = "ph.intportal.app";
const NAME: &str = "sis-login";

pub fn save(l: &Login) -> Result<(), String> {
    keychain::set(SERVICE, NAME, &serde_json::to_string(l).map_err(|e| e.to_string())?)
}

pub fn load() -> Option<Login> {
    serde_json::from_str(&keychain::get(SERVICE, NAME).ok()??).ok()
}

pub fn clear() {
    keychain::delete(SERVICE, NAME)
}
