use serde::{Deserialize, Serialize};

/// Monday = 1 through Sunday = 7, the order the week grid renders in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[repr(u8)]
pub enum Weekday {
    Monday = 1,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,
}

impl Weekday {
    pub const ALL: [Weekday; 7] = [
        Weekday::Monday,
        Weekday::Tuesday,
        Weekday::Wednesday,
        Weekday::Thursday,
        Weekday::Friday,
        Weekday::Saturday,
        Weekday::Sunday,
    ];

    /// SIS day codes, longest first so `TH` and `SUN` win over `T` and `S`.
    pub const CODES: [(&'static str, Weekday); 7] = [
        ("SUN", Weekday::Sunday),
        ("TH", Weekday::Thursday),
        ("M", Weekday::Monday),
        ("T", Weekday::Tuesday),
        ("W", Weekday::Wednesday),
        ("F", Weekday::Friday),
        ("S", Weekday::Saturday),
    ];

    pub fn number(self) -> u8 {
        self as u8
    }
}

/// One class block on one day. A course split into Lec and Lab, or meeting on
/// two days, is one session per occurrence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClassSession {
    pub subject_code: String,
    pub description: String,
    pub faculty: String,
    pub day: Weekday,
    /// Minutes from midnight.
    pub start: u16,
    pub end: u16,
    /// 0 for the first occurrence of a subject, day and time; 1 and up for a
    /// literal repeated SIS row, so ids stay unique.
    #[serde(default)]
    pub occurrence: u16,
}

impl ClassSession {
    /// Stable identity. Marks and colours key on it, so the format matches
    /// the old app's `ClassSession.id`.
    pub fn id(&self) -> String {
        let base = format!("{}-{}-{}-{}", self.subject_code, self.day.number(), self.start, self.end);
        if self.occurrence == 0 {
            base
        } else {
            format!("{base}-{}", self.occurrence)
        }
    }
}
