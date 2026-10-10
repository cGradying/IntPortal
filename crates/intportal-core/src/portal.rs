//! The PUP systems the app can connect to (spec 012, ADR 0005). SIS is ready;
//! Mabini is listed and "opens soon" until its client exists. Nothing here
//! signs in or stores anything: it only describes each portal.

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Ready,
    OpensSoon,
}

/// A five-tone ramp, darkest first, and one accent, as CSS hex colours.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Theme {
    pub ramp: [&'static str; 5],
    pub accent: &'static str,
}

/// A sign-in field, in the order the form shows them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Field {
    StudentNumber,
    Birthdate,
    Password,
}

/// At most `attempts` logins per `window_secs`, counted on the phone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Limits {
    pub attempts: u8,
    pub window_secs: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Portal {
    pub id: &'static str,
    pub name: &'static str,
    pub status: Status,
    pub theme: Theme,
    pub fields: &'static [Field],
    pub limits: Limits,
    /// Keychain service for this portal's login; never shared between portals.
    pub keychain_service: &'static str,
}

const LIMITS: Limits = Limits { attempts: 3, window_secs: 15 * 60 };

/// PUP's Student Information System. Keeps the service name the app already
/// uses, so existing logins keep working.
pub const SIS: Portal = Portal {
    id: "sis",
    name: "SIS",
    status: Status::Ready,
    theme: Theme { ramp: ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"], accent: "#e8b04a" },
    fields: &[Field::StudentNumber, Field::Birthdate, Field::Password],
    limits: LIMITS,
    keychain_service: "ph.intportal.app",
};

/// eMabini, the PUP Open University System's Moodle learning portal at
/// `emabini.pup.edu.ph`. Its login is a username and password (no birthdate);
/// the username is the student number, see `mabini_username`. Its brand
/// colour is `#700000`, the same maroon as the SIS, so Mabini is blue to tell
/// the two portals apart (the user's choice).
pub const MABINI: Portal = Portal {
    id: "mabini",
    name: "Mabini",
    status: Status::OpensSoon,
    theme: Theme { ramp: ["#0b2238", "#13466f", "#1f78a8", "#3fb4c9", "#a8efe4"], accent: "#5fd0d6" },
    fields: &[Field::StudentNumber, Field::Password],
    limits: LIMITS,
    keychain_service: "ph.intportal.app.mabini",
};

/// The registry, in the order the landing carousel shows it.
pub const ALL: [Portal; 2] = [SIS, MABINI];

pub fn get(id: &str) -> Option<&'static Portal> {
    ALL.iter().find(|p| p.id == id)
}

/// eMabini's username for a student number: lowercase with the dashes
/// removed, so `2024-12345-MN-0` becomes `202412345mn0`.
pub fn mabini_username(student_number: &str) -> String {
    student_number.chars().filter(|c| !c.is_whitespace() && *c != '-').flat_map(char::to_lowercase).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sis_is_ready_and_mabini_opens_soon() {
        assert_eq!(get("sis").unwrap().status, Status::Ready);
        assert_eq!(get("mabini").unwrap().status, Status::OpensSoon);
        assert!(get("nope").is_none());
    }

    #[test]
    fn ids_and_keychain_services_are_unique() {
        for (i, a) in ALL.iter().enumerate() {
            for b in &ALL[i + 1..] {
                assert_ne!(a.id, b.id);
                assert_ne!(a.keychain_service, b.keychain_service);
            }
        }
    }

    #[test]
    fn every_theme_is_six_hex_colours() {
        for p in ALL {
            for c in p.theme.ramp.iter().chain([&p.theme.accent]) {
                assert!(c.len() == 7 && c.starts_with('#') && c[1..].chars().all(|h| h.is_ascii_hexdigit()), "{} {c}", p.id);
            }
        }
    }

    #[test]
    fn mabini_has_no_birthdate_field() {
        assert_eq!(MABINI.fields, &[Field::StudentNumber, Field::Password]);
        assert!(SIS.fields.contains(&Field::Birthdate));
    }

    #[test]
    fn mabini_username_is_lowercase_without_dashes() {
        assert_eq!(mabini_username("2024-12345-MN-0"), "202412345mn0");
        assert_eq!(mabini_username(" 2024-12345-mn-0 "), "202412345mn0");
    }
}
