//! The school systems the app can connect to (spec 012, ADR 0005). PUP's SIS
//! and eMabini are ready; `OpensSoon` is for a portal listed before it is
//! built, such as the state-university placeholders. Nothing here signs in or
//! stores anything: it only describes each portal and how its tile portal looks.

use serde::Serialize;
use std::sync::LazyLock;

use crate::schools;

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

/// How the frame's corners are cut on the landing (spec 010).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Corner {
    Square,
    Cut,
    Arch,
}

/// The tile portal's frame: `cols` by `rows` blocks, one block thick.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Shape {
    pub cols: u8,
    pub rows: u8,
    pub corner: Corner,
}

/// The pattern inside the portal's opening.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Motif {
    Swirl,
    Ripple,
    Bloom,
    Rain,
    Lattice,
    Aurora,
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
    /// The short name on the carousel.
    pub name: &'static str,
    /// The school, written out.
    pub school: &'static str,
    /// Its region, for the hub's "your region" list.
    pub region: &'static str,
    pub status: Status,
    pub theme: Theme,
    pub shape: Shape,
    pub motif: Motif,
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
    school: "Polytechnic University of the Philippines",
    region: "NCR",
    status: Status::Ready,
    theme: Theme { ramp: ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"], accent: "#e8b04a" },
    shape: Shape { cols: 6, rows: 8, corner: Corner::Square },
    motif: Motif::Swirl,
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
    school: "PUP Open University System",
    region: "NCR",
    status: Status::Ready,
    theme: Theme { ramp: ["#0b2238", "#13466f", "#1f78a8", "#3fb4c9", "#a8efe4"], accent: "#5fd0d6" },
    shape: Shape { cols: 7, rows: 7, corner: Corner::Cut },
    motif: Motif::Ripple,
    fields: &[Field::StudentNumber, Field::Password],
    limits: LIMITS,
    keychain_service: "ph.intportal.app.mabini",
};

/// A state university listed before its portal is built: a name, a look and
/// "Opens soon", no sign-in. The palettes are placeholders until the
/// universities reference (docs/specs/reference) confirms each school's colours.
const fn soon(id: &'static str, name: &'static str, school: &'static str, region: &'static str, theme: Theme, shape: Shape, motif: Motif) -> Portal {
    Portal { id, name, school, region, status: Status::OpensSoon, theme, shape, motif, fields: &[], limits: LIMITS, keychain_service: id }
}

pub const UP: Portal = soon(
    "up",
    "UP",
    "University of the Philippines",
    "NCR",
    Theme { ramp: ["#0d2418", "#17452c", "#2a7a46", "#6cbf6a", "#d4f2b0"], accent: "#9fe07a" },
    Shape { cols: 6, rows: 9, corner: Corner::Arch },
    Motif::Bloom,
);

pub const TUP: Portal = soon(
    "tup",
    "TUP",
    "Technological University of the Philippines",
    "NCR",
    Theme { ramp: ["#16181f", "#2c3140", "#56607a", "#9aa6bd", "#e6ebf5"], accent: "#ff6b5f" },
    Shape { cols: 8, rows: 7, corner: Corner::Square },
    Motif::Lattice,
);

pub const PNU: Portal = soon(
    "pnu",
    "PNU",
    "Philippine Normal University",
    "NCR",
    Theme { ramp: ["#160f33", "#2d1f66", "#5440b0", "#9a86f0", "#e2dbff"], accent: "#c8b6ff" },
    Shape { cols: 5, rows: 9, corner: Corner::Square },
    Motif::Rain,
);

pub const BULSU: Portal = soon(
    "bulsu",
    "BulSU",
    "Bulacan State University",
    "Central Luzon",
    Theme { ramp: ["#2a1405", "#5c2c08", "#b0560f", "#f0a030", "#ffe3a3"], accent: "#ffc04d" },
    Shape { cols: 7, rows: 8, corner: Corner::Cut },
    Motif::Aurora,
);

const MOTIFS: [Motif; 6] = [Motif::Swirl, Motif::Ripple, Motif::Bloom, Motif::Rain, Motif::Lattice, Motif::Aurora];

/// A listed school's portal, built from its row in [`schools`]. The shape
/// comes from a hash of the id; the motif steps along the list, so
/// neighbours on the carousel never share one.
fn school(i: usize, &(id, name, school, region, base): &schools::Row) -> Portal {
    let leak = |s: String| -> &'static str { Box::leak(s.into_boxed_str()) };
    let (ramp, accent) = schools::theme_from(base);
    let h = id.bytes().fold(2166136261u32, |h, b| (h ^ b as u32).wrapping_mul(16777619));
    let corner = [Corner::Square, Corner::Cut, Corner::Arch][(h >> 8) as usize % 3];
    let shape = Shape { cols: 5 + (h % 4) as u8, rows: 7 + ((h >> 4) % 3) as u8, corner };
    let theme = Theme { ramp: ramp.map(leak), accent: leak(accent) };
    soon(id, name, school, region, theme, shape, MOTIFS[i % MOTIFS.len()])
}

/// The registry, in the order the landing carousel shows it: PUP's portals
/// and the hand-drawn placeholders first, then every listed school.
pub static ALL: LazyLock<Vec<Portal>> =
    LazyLock::new(|| [SIS, MABINI, UP, TUP, PNU, BULSU].into_iter().chain(schools::ROWS.iter().enumerate().map(|(i, r)| school(i, r))).collect());

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
    fn sis_and_mabini_are_ready() {
        assert_eq!(get("sis").unwrap().status, Status::Ready);
        assert_eq!(get("mabini").unwrap().status, Status::Ready);
        assert!(get("nope").is_none());
    }

    #[test]
    fn only_pup_portals_are_ready_and_placeholders_have_no_form() {
        for p in ALL.iter() {
            let ready = matches!(p.id, "sis" | "mabini");
            assert_eq!(p.status == Status::Ready, ready, "{}", p.id);
            if !ready {
                assert!(p.fields.is_empty(), "{}", p.id);
            }
        }
    }

    #[test]
    fn every_shape_fits_the_landing_grid_and_looks_differ() {
        for p in ALL.iter() {
            assert!((5..=8).contains(&p.shape.cols) && (7..=9).contains(&p.shape.rows), "{}", p.id);
        }
        // Neighbours on the carousel are what the student compares.
        for w in ALL.windows(2) {
            let (a, b) = (&w[0], &w[1]);
            assert!(a.shape != b.shape || a.motif != b.motif, "{} and {} look alike", a.id, b.id);
            assert_ne!(a.theme.accent, b.theme.accent, "{} and {}", a.id, b.id);
        }
        assert!(ALL.len() >= 100);
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
        for p in ALL.iter() {
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
