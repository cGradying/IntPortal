//! Each student's store key: 32 random bytes in the keychain, named by
//! the store's file. Made once, on the first open of that store.
use super::keychain;

const SERVICE: &str = "ph.intportal.app.db";

pub fn get_or_create(file: &str) -> Result<[u8; 32], String> {
    match keychain::get(SERVICE, file)? {
        Some(hex) => parse(&hex).ok_or_else(|| "The store key in the keychain is damaged.".to_string()),
        // Only a missing key is made anew. Any other keychain error (say,
        // before the phone's first unlock) has already returned above and
        // must not replace a real key.
        None => {
            let mut key = [0u8; 32];
            getrandom::fill(&mut key).map_err(|e| e.to_string())?;
            keychain::set(SERVICE, file, &key.iter().map(|b| format!("{b:02x}")).collect::<String>())?;
            Ok(key)
        }
    }
}

fn parse(hex: &str) -> Option<[u8; 32]> {
    let mut key = [0u8; 32];
    if hex.len() != 64 {
        return None;
    }
    for (i, b) in key.iter_mut().enumerate() {
        *b = u8::from_str_radix(hex.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(key)
}
