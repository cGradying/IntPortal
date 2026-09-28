//! Which PUP campus a student number belongs to (legacy spec 10). Only
//! Sta. Mesa's code (`MN`) is publicly confirmed; the others are never guessed.

use regex::Regex;
use serde::Serialize;
use std::sync::LazyLock;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Campus {
    pub code: Option<&'static str>,
    pub name: &'static str,
    pub region: &'static str,
}

const fn c(code: Option<&'static str>, name: &'static str, region: &'static str) -> Campus {
    Campus { code, name, region }
}

/// PUP's campuses and branches (Wikipedia, researched 2026-09-23).
pub const ALL: [Campus; 25] = [
    c(Some("MN"), "Sta. Mesa", "Manila"),
    c(None, "San Juan", "Metro Manila"),
    c(None, "Parañaque", "Metro Manila"),
    c(None, "Taguig", "Metro Manila"),
    c(None, "Quezon City", "Metro Manila"),
    c(None, "Caloocan", "Metro Manila"),
    c(None, "Mariveles", "Bataan"),
    c(None, "Pulilan", "Bulacan"),
    c(None, "Sta. Maria", "Bulacan"),
    c(None, "Cabiao", "Nueva Ecija"),
    c(None, "Maragondon", "Cavite"),
    c(None, "Alfonso", "Cavite"),
    c(None, "Biñan", "Laguna"),
    c(None, "Calauan", "Laguna"),
    c(None, "San Pedro", "Laguna"),
    c(None, "Sta. Rosa", "Laguna"),
    c(None, "Sto. Tomas", "Batangas"),
    c(None, "Talisay", "Batangas"),
    c(None, "Mulanay", "Quezon"),
    c(None, "Lopez", "Quezon"),
    c(None, "Unisan", "Quezon"),
    c(None, "Ragay", "Camarines Sur"),
    c(None, "Bansud", "Mindoro"),
    c(None, "Sablayan", "Mindoro"),
    c(None, "Leyte", "Leyte"),
];

static NUMBER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\d{4}-\d{5}-([A-Za-z]{2})-\d{1,2}$").unwrap());

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Resolution {
    Known { campus: Campus },
    UnknownCode { code: String },
    Incomplete,
}

/// The two-letter code in a fully typed student number, uppercased.
pub fn code(student_number: &str) -> Option<String> {
    NUMBER.captures(student_number.trim()).map(|c| c[1].to_ascii_uppercase())
}

pub fn resolve(student_number: &str) -> Resolution {
    match code(student_number) {
        None => Resolution::Incomplete,
        Some(code) => match ALL.iter().find(|c| c.code == Some(code.as_str())) {
            Some(campus) => Resolution::Known { campus: campus.clone() },
            None => Resolution::UnknownCode { code },
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves() {
        assert_eq!(resolve("2026-00000-MN-0"), Resolution::Known { campus: ALL[0].clone() });
        assert_eq!(resolve("2026-00000-TG-0"), Resolution::UnknownCode { code: "TG".into() });
        assert_eq!(resolve("2026-000"), Resolution::Incomplete);
    }

    #[test]
    fn codes() {
        assert_eq!(code("2026-00000-MN-0").as_deref(), Some("MN"));
        assert_eq!(code("2026-00000-MN-12").as_deref(), Some("MN"));
        assert_eq!(code("  2026-00000-mn-0  ").as_deref(), Some("MN"));
        assert_eq!(code("2026-00000-MN-123"), None);
    }

    #[test]
    fn only_sta_mesa_has_a_confirmed_code() {
        let coded: Vec<&str> = ALL.iter().filter(|c| c.code.is_some()).map(|c| c.name).collect();
        assert_eq!(coded, ["Sta. Mesa"]);
    }
}
