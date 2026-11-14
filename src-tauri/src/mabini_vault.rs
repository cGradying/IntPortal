//! eMabini's login, in its own keychain entry; never mixed with the SIS's.
use super::{keychain, MabiniLogin};

const NAME: &str = "mabini-login";

pub fn save(l: &MabiniLogin) -> Result<(), String> {
    keychain::set(intportal_core::portal::MABINI.keychain_service, NAME, &serde_json::to_string(l).map_err(|e| e.to_string())?)
}

pub fn load() -> Option<MabiniLogin> {
    serde_json::from_str(&keychain::get(intportal_core::portal::MABINI.keychain_service, NAME).ok()??).ok()
}

pub fn clear() {
    keychain::delete(intportal_core::portal::MABINI.keychain_service, NAME)
}
