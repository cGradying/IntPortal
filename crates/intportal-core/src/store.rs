//! Everything the app keeps on the device, in one SQLite file (ADR-0002).
//! One JSON value per key: the data is small and read whole.

use crate::grades::{GradeReport, Goals};
use crate::model::ClassSession;
use crate::notes::Note;
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
        db.execute_batch(
            "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, json TEXT NOT NULL);
             CREATE TABLE IF NOT EXISTS notes (key TEXT PRIMARY KEY, text TEXT NOT NULL, title TEXT, updated INTEGER NOT NULL);",
        )?;
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

    /// Every note, the latest edit first.
    pub fn notes(&self) -> Result<Vec<Note>, StoreError> {
        let mut q = self.db.prepare("SELECT key, text, title, updated FROM notes ORDER BY updated DESC, key")?;
        let rows = q.query_map([], |r| Ok(Note { key: r.get(0)?, text: r.get(1)?, title: r.get(2)?, updated: r.get(3)? }))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Saves one note. Blank text deletes it, so an emptied note doesn't
    /// linger in the list. `title` empty keeps the one already stored.
    pub fn set_note(&self, key: &str, text: &str, title: Option<&str>, now: i64) -> Result<(), StoreError> {
        if text.trim().is_empty() {
            self.db.execute("DELETE FROM notes WHERE key = ?1", [key])?;
        } else {
            self.db.execute(
                "INSERT INTO notes (key, text, title, updated) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(key) DO UPDATE SET text = excluded.text, title = COALESCE(excluded.title, notes.title), updated = excluded.updated",
                params![key, text, title, now],
            )?;
        }
        Ok(())
    }

    /// Sign-out: nothing of the account stays on the device, notes included.
    pub fn wipe(&self) -> Result<(), StoreError> {
        self.db.execute_batch("DELETE FROM kv; DELETE FROM notes;")?;
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

    #[test]
    fn notes_save_update_list_newest_first_and_blank_deletes() {
        let store = Store::in_memory().unwrap();
        store.set_note("class:COMP 20073", "Quiz Friday", Some("Data Structures"), 100).unwrap();
        store.set_note("day:2026-09-28", "Bring laptop", None, 200).unwrap();
        store.set_note("class:COMP 20073", "Quiz Friday, trees", None, 300).unwrap();
        let notes = store.notes().unwrap();
        assert_eq!(notes.iter().map(|n| (n.key.as_str(), n.text.as_str(), n.updated)).collect::<Vec<_>>(), [("class:COMP 20073", "Quiz Friday, trees", 300), ("day:2026-09-28", "Bring laptop", 200)]);
        assert_eq!(notes[0].title.as_deref(), Some("Data Structures"));
        store.set_note("day:2026-09-28", "  \n ", None, 400).unwrap();
        assert_eq!(store.notes().unwrap().len(), 1);
        store.wipe().unwrap();
        assert!(store.notes().unwrap().is_empty());
    }
}
