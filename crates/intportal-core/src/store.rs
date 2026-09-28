//! Everything the app keeps on the device, in one SQLite file (ADR-0002).
//! One JSON value per key: the data is small and read whole.

use crate::grades::{GradeReport, Goals};
use crate::model::ClassSession;
use crate::today::Marks;
use rusqlite::{params, Connection, OptionalExtension};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;

/// What every screen reads, loaded in one go so the first frame already has
/// the week in it.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Snapshot {
    pub sessions: Vec<ClassSession>,
    pub grades: Option<GradeReport>,
    pub history: Vec<GradeReport>,
    pub marks: Marks,
    /// Subject code to a CSS colour.
    pub colors: BTreeMap<String, String>,
    #[serde(default)]
    pub goals: Goals,
    /// The host that last proved good, tried first next time.
    pub host: Option<String>,
    /// RFC 3339, written by the shell.
    pub last_synced: Option<String>,
}

pub struct Store {
    db: Connection,
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error(transparent)]
    Sql(#[from] rusqlite::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

impl Store {
    pub fn open(path: &Path) -> Result<Store, StoreError> {
        Store::init(Connection::open(path)?)
    }

    pub fn in_memory() -> Result<Store, StoreError> {
        Store::init(Connection::open_in_memory()?)
    }

    fn init(db: Connection) -> Result<Store, StoreError> {
        db.execute_batch("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, json TEXT NOT NULL)")?;
        Ok(Store { db })
    }

    fn get<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>, StoreError> {
        let json: Option<String> =
            self.db.query_row("SELECT json FROM kv WHERE key = ?1", [key], |r| r.get(0)).optional()?;
        Ok(json.map(|j| serde_json::from_str(&j)).transpose()?)
    }

    fn put<T: Serialize>(&self, key: &str, value: &T) -> Result<(), StoreError> {
        self.db.execute(
            "INSERT INTO kv (key, json) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET json = excluded.json",
            params![key, serde_json::to_string(value)?],
        )?;
        Ok(())
    }

    pub fn load(&self) -> Result<Snapshot, StoreError> {
        Ok(Snapshot {
            sessions: self.get("sessions")?.unwrap_or_default(),
            grades: self.get::<Option<_>>("grades")?.flatten(),
            history: self.get("history")?.unwrap_or_default(),
            marks: self.get("marks")?.unwrap_or_default(),
            colors: self.get("colors")?.unwrap_or_default(),
            goals: self.get("goals")?.unwrap_or_default(),
            host: self.get::<Option<_>>("host")?.flatten(),
            last_synced: self.get::<Option<_>>("last_synced")?.flatten(),
        })
    }

    pub fn save(&self, s: &Snapshot) -> Result<(), StoreError> {
        self.put("sessions", &s.sessions)?;
        self.put("grades", &s.grades)?;
        self.put("history", &s.history)?;
        self.put("marks", &s.marks)?;
        self.put("colors", &s.colors)?;
        self.put("goals", &s.goals)?;
        self.put("host", &s.host)?;
        self.put("last_synced", &s.last_synced)
    }

    /// Sign-out: nothing of the account stays on the device.
    pub fn wipe(&self) -> Result<(), StoreError> {
        self.db.execute("DELETE FROM kv", [])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Weekday;
    use crate::today::{Date, Mark, Marks, Slot};

    #[test]
    fn round_trips_and_wipes() {
        let store = Store::in_memory().unwrap();
        assert_eq!(store.load().unwrap(), Snapshot::default());

        let session = ClassSession {
            subject_code: "COMP 20073".into(),
            description: "Data Structures".into(),
            faculty: "SANTOS, JUAN".into(),
            day: Weekday::Tuesday,
            start: 840,
            end: 960,
            occurrence: 0,
        };
        let mut snap = Snapshot { sessions: vec![session.clone()], host: Some("sis8.pup.edu.ph".into()), ..Default::default() };
        snap.marks.mode.set(&session.id(), Some(Date::new(2026, 8, 3)), Some(Mark::Vacant));
        snap.marks.moved.set(&session.id(), None, Some(Slot { day: Weekday::Friday, start: 600, end: 720 }));
        snap.colors.insert("COMP 20073".into(), "#3b82f6".into());
        snap.goals = Goals { target_gpa: Some(1.5), program_units: Some(152.0) };
        store.save(&snap).unwrap();
        assert_eq!(store.load().unwrap(), snap);

        store.wipe().unwrap();
        assert_eq!(store.load().unwrap(), Snapshot::default());
    }

    #[test]
    fn marks_saved_before_moves_existed_still_load() {
        let old = r#"{"term":{"A-1-0-60":"online"},"weekly":{"A-1-0-60":{"2026-08-03":"vacant"}}}"#;
        let marks: Marks = serde_json::from_str(old).unwrap();
        assert_eq!(marks.mode.get("A-1-0-60", Date::new(2026, 8, 5)), Some(Mark::Vacant));
        assert_eq!(marks.mode.get("A-1-0-60", Date::new(2026, 8, 10)), Some(Mark::Online));
        assert_eq!(marks.moved, Default::default());
    }
}
