//! Everything the app keeps on the device, in one SQLite file (ADR-0002),
//! encrypted with SQLCipher under a key the shell keeps in the keychain.
//! One JSON value per key: the data is small and read whole.

use crate::grades::{GradeReport, Goals};
use crate::model::ClassSession;
use crate::notes::Note;
use crate::study::{Deck, Stats};
use crate::syllabus::Plan;
use crate::today::Marks;
use rusqlite::{params, Connection, ErrorCode, OptionalExtension};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

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
    /// Subject code to its syllabus plan.
    #[serde(default)]
    pub syllabus: BTreeMap<String, Plan>,
    /// The host that last proved good, tried first next time.
    pub host: Option<String>,
    /// RFC 3339, written by the shell.
    pub last_synced: Option<String>,
}

/// The file one student's data lives in. Each student number gets its own,
/// so a second student signing in on the same phone never sees (or wipes)
/// the first one's notes. The name hides the number (FNV-1a), it doesn't
/// protect it; the store's own encryption does that.
pub fn account_file(student_number: &str) -> String {
    let key: String = student_number.chars().filter(|c| c.is_ascii_alphanumeric()).map(|c| c.to_ascii_uppercase()).collect();
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in key.bytes() {
        h = (h ^ u64::from(b)).wrapping_mul(0x100_0000_01b3);
    }
    format!("account-{h:016x}.sqlite")
}

/// One message of the LAR chat.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Turn {
    pub role: String,
    pub text: String,
    pub at: i64,
    pub ask: bool,
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
    #[error(transparent)]
    Io(#[from] std::io::Error),
    /// The file is encrypted under a different key, or isn't a database.
    #[error("This store can't be opened with this phone's key.")]
    Locked,
}

/// Opens with the key and proves it by reading the schema.
fn keyed(path: &Path, key: &str) -> rusqlite::Result<Connection> {
    let db = Connection::open(path)?;
    db.execute_batch(&format!("PRAGMA key = \"{key}\";"))?;
    readable(&db)?;
    Ok(db)
}

fn readable(db: &Connection) -> rusqlite::Result<()> {
    db.query_row("SELECT count(*) FROM sqlite_master", [], |_| Ok(()))
}

fn not_a_database(e: &rusqlite::Error) -> bool {
    matches!(e, rusqlite::Error::SqliteFailure(f, _) if f.code == ErrorCode::NotADatabase)
}

/// Rewrites a plain store as an encrypted copy beside it, then swaps the
/// copy in with one rename. A crash before the rename leaves the plain file
/// whole, and the next open starts over.
fn encrypt_in_place(path: &Path, key: &str) -> Result<(), StoreError> {
    let mut enc = path.as_os_str().to_owned();
    enc.push(".enc");
    let enc = PathBuf::from(enc);
    if enc.exists() {
        std::fs::remove_file(&enc)?;
    }
    {
        let plain = Connection::open(path)?;
        plain.execute(&format!("ATTACH DATABASE ?1 AS enc KEY \"{key}\""), [enc.to_string_lossy()])?;
        plain.query_row("SELECT sqlcipher_export('enc')", [], |_| Ok(()))?;
        plain.execute_batch("DETACH DATABASE enc;")?;
    }
    std::fs::File::open(&enc)?.sync_all()?;
    std::fs::rename(&enc, path)?;
    Ok(())
}

impl Store {
    /// Opens this student's store with their 32-byte key. A store from
    /// before encryption is encrypted in place first.
    pub fn open(path: &Path, key: &[u8; 32]) -> Result<Store, StoreError> {
        let hex: String = key.iter().map(|b| format!("{b:02x}")).collect();
        let key = format!("x'{hex}'");
        match keyed(path, &key) {
            Ok(db) => Store::init(db),
            Err(e) if not_a_database(&e) => {
                if readable(&Connection::open(path)?).is_err() {
                    return Err(StoreError::Locked);
                }
                encrypt_in_place(path, &key)?;
                Store::init(keyed(path, &key)?)
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Unencrypted, for targets with no keychain to hold a key yet.
    // ponytail: Android stays plain until the Keystore lands with #15.
    pub fn open_plain(path: &Path) -> Result<Store, StoreError> {
        Store::init(Connection::open(path)?)
    }

    pub fn in_memory() -> Result<Store, StoreError> {
        Store::init(Connection::open_in_memory()?)
    }

    fn init(db: Connection) -> Result<Store, StoreError> {
        db.execute_batch(
            "PRAGMA secure_delete = ON;
             CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, json TEXT NOT NULL);
             CREATE TABLE IF NOT EXISTS notes (key TEXT PRIMARY KEY, text TEXT NOT NULL, title TEXT, updated INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS decks (id TEXT PRIMARY KEY, json TEXT NOT NULL);
             CREATE TABLE IF NOT EXISTS chunks (note_key TEXT NOT NULL, n INTEGER NOT NULL, text TEXT NOT NULL, vec BLOB NOT NULL, note_updated INTEGER NOT NULL, model TEXT NOT NULL, PRIMARY KEY (note_key, n));
             CREATE TABLE IF NOT EXISTS turns (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, text TEXT NOT NULL, at INTEGER NOT NULL, ask INTEGER NOT NULL);",
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
            syllabus: self.get("syllabus")?.unwrap_or_default(),
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
        self.put("syllabus", &s.syllabus)?;
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
            self.db.execute("DELETE FROM chunks WHERE note_key = ?1", [key])?;
        } else {
            self.db.execute(
                "INSERT INTO notes (key, text, title, updated) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(key) DO UPDATE SET text = excluded.text, title = COALESCE(excluded.title, notes.title), updated = excluded.updated",
                params![key, text, title, now],
            )?;
        }
        Ok(())
    }

    /// Notes with no chunks from `model` at their current edit. The AI embeds
    /// these just before a search; `set_note` itself never embeds.
    pub fn stale_notes(&self, model: &str) -> Result<Vec<Note>, StoreError> {
        let mut q = self.db.prepare(
            "SELECT key, text, title, updated FROM notes n WHERE NOT EXISTS
             (SELECT 1 FROM chunks c WHERE c.note_key = n.key AND c.note_updated = n.updated AND c.model = ?1)
             ORDER BY updated DESC, key",
        )?;
        let rows = q.query_map([model], |r| Ok(Note { key: r.get(0)?, text: r.get(1)?, title: r.get(2)?, updated: r.get(3)? }))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Replaces a note's chunks with `chunks` (text and unit vector each).
    pub fn replace_chunks(&self, note_key: &str, note_updated: i64, model: &str, chunks: &[(String, Vec<f32>)]) -> Result<(), StoreError> {
        self.db.execute("DELETE FROM chunks WHERE note_key = ?1", [note_key])?;
        for (n, (text, vec)) in chunks.iter().enumerate() {
            let blob: Vec<u8> = vec.iter().flat_map(|f| f.to_le_bytes()).collect();
            self.db.execute(
                "INSERT INTO chunks (note_key, n, text, vec, note_updated, model) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![note_key, n as i64, text, blob, note_updated, model],
            )?;
        }
        Ok(())
    }

    /// Every chunk made by `model`: (note key, text, vector).
    pub fn chunks(&self, model: &str) -> Result<Vec<(String, String, Vec<f32>)>, StoreError> {
        let mut q = self.db.prepare("SELECT note_key, text, vec FROM chunks WHERE model = ?1 ORDER BY note_key, n")?;
        let rows = q.query_map([model], |r| {
            let blob: Vec<u8> = r.get(2)?;
            let vec = blob.chunks(4).filter_map(|b| b.try_into().ok().map(f32::from_le_bytes)).collect();
            Ok((r.get(0)?, r.get(1)?, vec))
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn decks(&self) -> Result<Vec<Deck>, StoreError> {
        let mut q = self.db.prepare("SELECT json FROM decks ORDER BY id")?;
        let rows = q.query_map([], |r| r.get::<_, String>(0))?;
        rows.map(|j| Ok(serde_json::from_str(&j?)?)).collect()
    }

    pub fn deck(&self, id: &str) -> Result<Option<Deck>, StoreError> {
        let json: Option<String> = self.db.query_row("SELECT json FROM decks WHERE id = ?1", [id], |r| r.get(0)).optional()?;
        Ok(json.map(|j| serde_json::from_str(&j)).transpose()?)
    }

    pub fn save_deck(&self, deck: &Deck) -> Result<(), StoreError> {
        self.db.execute(
            "INSERT INTO decks (id, json) VALUES (?1, ?2) ON CONFLICT(id) DO UPDATE SET json = excluded.json",
            params![deck.id, serde_json::to_string(deck)?],
        )?;
        Ok(())
    }

    pub fn delete_deck(&self, id: &str) -> Result<(), StoreError> {
        self.db.execute("DELETE FROM decks WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn study_stats(&self) -> Result<Stats, StoreError> {
        Ok(self.get("study_stats")?.unwrap_or_default())
    }

    pub fn save_study_stats(&self, s: &Stats) -> Result<(), StoreError> {
        self.put("study_stats", s)
    }

    /// Sign-out: drops what came from SIS (schedule, grades, the server)
    /// and keeps what the student made: notes, decks and streak, syllabus
    /// pages, goals, class marks and colours.
    /// What the last eMabini sync read. It lives in the student's own store,
    /// next to but apart from the SIS data.
    pub fn mabini(&self) -> Result<crate::mabini::MabiniData, StoreError> {
        Ok(self.get("mabini")?.unwrap_or_default())
    }

    pub fn save_mabini(&self, data: &crate::mabini::MabiniData) -> Result<(), StoreError> {
        self.put("mabini", data)
    }

    pub fn forget_mabini(&self) -> Result<(), StoreError> {
        self.db.execute("DELETE FROM kv WHERE key = 'mabini'", [])?;
        Ok(())
    }

    pub fn forget_sis(&self) -> Result<(), StoreError> {
        self.db.execute("DELETE FROM kv WHERE key IN ('sessions', 'grades', 'history', 'host', 'last_synced')", [])?;
        // What LAR said may quote those grades and classes.
        self.clear_turns()
    }

    /// Adds one chat message. `role` is "me" or "lar"; `ask` marks a message the
    /// model answered, the only ones it is shown again. Keeps the last 60.
    pub fn add_turn(&self, role: &str, text: &str, at: i64, ask: bool) -> Result<(), StoreError> {
        self.db.execute("INSERT INTO turns (role, text, at, ask) VALUES (?1, ?2, ?3, ?4)", params![role, text, at, ask])?;
        self.db.execute("DELETE FROM turns WHERE id <= (SELECT MAX(id) FROM turns) - 60", [])?;
        Ok(())
    }

    /// The last `limit` messages, oldest first.
    pub fn turns(&self, limit: usize) -> Result<Vec<Turn>, StoreError> {
        let mut q = self.db.prepare("SELECT role, text, at, ask FROM turns ORDER BY id DESC LIMIT ?1")?;
        let rows = q.query_map([limit as i64], |r| Ok(Turn { role: r.get(0)?, text: r.get(1)?, at: r.get(2)?, ask: r.get(3)? }))?;
        let mut v = rows.collect::<Result<Vec<_>, _>>()?;
        v.reverse();
        Ok(v)
    }

    pub fn clear_turns(&self) -> Result<(), StoreError> {
        self.db.execute("DELETE FROM turns", [])?;
        Ok(())
    }

    /// Erase everything on the device, the student's own work included.
    pub fn wipe(&self) -> Result<(), StoreError> {
        self.db.execute_batch("DELETE FROM kv; DELETE FROM notes; DELETE FROM decks; DELETE FROM chunks; DELETE FROM turns;")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Weekday;
    use crate::today::{Date, Mark, Marks, Slot};

    #[test]
    fn mabini_data_is_kept_apart_from_the_sis_data() {
        let store = Store::in_memory().unwrap();
        assert_eq!(store.mabini().unwrap(), crate::mabini::MabiniData::default());
        let data = crate::mabini::MabiniData { last_synced: Some(5), ..Default::default() };
        store.save_mabini(&data).unwrap();
        assert_eq!(store.mabini().unwrap(), data);
        store.forget_sis().unwrap();
        assert_eq!(store.mabini().unwrap(), data, "signing out of the SIS leaves eMabini alone");
        store.forget_mabini().unwrap();
        assert_eq!(store.mabini().unwrap(), crate::mabini::MabiniData::default());
    }

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
    fn sign_out_forgets_sis_data_but_keeps_the_students_work() {
        let store = Store::in_memory().unwrap();
        let mut snap = Snapshot { host: Some("sis8.pup.edu.ph".into()), last_synced: Some("1".into()), ..Default::default() };
        snap.sessions.push(ClassSession { subject_code: "A".into(), description: String::new(), faculty: String::new(), day: Weekday::Monday, start: 0, end: 60, occurrence: 0 });
        snap.grades = Some(GradeReport { subjects: vec![], summary: BTreeMap::new(), school_year: None, semester: None });
        snap.colors.insert("A".into(), "var(--s2)".into());
        snap.goals.target_gpa = Some(1.5);
        snap.marks.mode.set("A-1-0-60", None, Some(Mark::Online));
        snap.syllabus.insert("A".into(), Plan { target: Some(90.0), ..Default::default() });
        store.save(&snap).unwrap();
        store.set_note("class:A", "keep me", None, 1).unwrap();
        store.save_deck(&Deck { id: "d".into(), name: "D".into(), subject: None, cards: vec![] }).unwrap();
        store.save_study_stats(&Stats { streak: 3, ..Default::default() }).unwrap();

        store.forget_sis().unwrap();
        let kept = store.load().unwrap();
        assert_eq!((kept.sessions.len(), kept.grades, kept.host, kept.last_synced), (0, None, None, None));
        assert_eq!((kept.colors, kept.goals, kept.marks, kept.syllabus), (snap.colors, snap.goals, snap.marks, snap.syllabus));
        assert_eq!((store.notes().unwrap().len(), store.decks().unwrap().len(), store.study_stats().unwrap().streak), (1, 1, 3));
    }

    #[test]
    fn each_student_number_gets_its_own_file() {
        assert_eq!(account_file("2023-00123-MN-0"), account_file(" 2023-00123-mn-0 "));
        assert_ne!(account_file("2023-00123-MN-0"), account_file("2023-00124-MN-0"));
        let f = account_file("2023-00123-MN-0");
        assert!(f.starts_with("account-") && f.ends_with(".sqlite") && !f.contains("2023"));
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

    #[test]
    fn chunks_go_stale_with_an_edit_or_a_model_change_and_leave_with_the_note() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "alpha", None, 100).unwrap();
        store.set_note("note:b", "beta", None, 100).unwrap();
        assert_eq!(store.stale_notes("m1").unwrap().len(), 2);
        store.replace_chunks("note:a", 100, "m1", &[("alpha".into(), vec![1.0, 0.0]), ("al".into(), vec![0.0, 1.0])]).unwrap();
        assert_eq!(store.stale_notes("m1").unwrap().iter().map(|n| n.key.as_str()).collect::<Vec<_>>(), ["note:b"]);
        assert_eq!(store.stale_notes("m2").unwrap().len(), 2, "another model's vectors are not reusable");
        assert_eq!(store.chunks("m1").unwrap(), [("note:a".to_string(), "alpha".to_string(), vec![1.0, 0.0]), ("note:a".to_string(), "al".to_string(), vec![0.0, 1.0])]);
        store.set_note("note:a", "alpha edited", None, 200).unwrap();
        assert_eq!(store.stale_notes("m1").unwrap().len(), 2, "an edit makes the note stale");
        store.replace_chunks("note:a", 200, "m1", &[("x".into(), vec![1.0, 0.0])]).unwrap();
        assert_eq!(store.chunks("m1").unwrap().len(), 1, "replace drops the old chunks");
        store.set_note("note:a", "", None, 300).unwrap();
        assert!(store.chunks("m1").unwrap().is_empty(), "deleting a note drops its chunks");
        store.replace_chunks("note:b", 100, "m1", &[("beta".into(), vec![1.0])]).unwrap();
        store.wipe().unwrap();
        assert!(store.chunks("m1").unwrap().is_empty());
    }

    #[test]
    fn decks_round_trip_and_wipe() {
        use crate::study::{Card, Memory};
        let store = Store::in_memory().unwrap();
        let mut deck = Deck { id: "d1".into(), name: "DSA".into(), subject: Some("COMP 20073".into()), cards: vec![] };
        deck.cards.push(Card { id: String::new(), front: "Stack".into(), back: "LIFO".into(), accepted: vec![], memory: Memory::new(0) });
        deck.settle_new_cards(100);
        store.save_deck(&deck).unwrap();
        assert_eq!(store.deck("d1").unwrap(), Some(deck.clone()));
        assert_eq!(store.decks().unwrap()[0].cards[0].id, "1");
        assert_eq!(store.decks().unwrap()[0].cards[0].memory.due, 100);
        store.wipe().unwrap();
        assert!(store.decks().unwrap().is_empty());
    }

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("intportal-store-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("account.sqlite")
    }

    fn header(path: &Path) -> Vec<u8> {
        std::fs::read(path).unwrap()[..16].to_vec()
    }

    const KEY: [u8; 32] = [7; 32];

    #[test]
    fn encrypted_round_trip() {
        let path = scratch("round");
        let snap = Snapshot { host: Some("sis8.pup.edu.ph".into()), ..Snapshot::default() };
        Store::open(&path, &KEY).unwrap().save(&snap).unwrap();
        assert_eq!(Store::open(&path, &KEY).unwrap().load().unwrap(), snap);
        assert_ne!(header(&path), b"SQLite format 3\0");
    }

    #[test]
    fn the_wrong_key_is_locked_out() {
        let path = scratch("wrong");
        Store::open(&path, &KEY).unwrap().save(&Snapshot::default()).unwrap();
        assert!(matches!(Store::open(&path, &[8; 32]), Err(StoreError::Locked)));
    }

    #[test]
    fn a_plain_store_is_encrypted_in_place_and_keeps_its_rows() {
        let path = scratch("plain");
        let plain = Connection::open(&path).unwrap();
        plain.execute_batch("CREATE TABLE kv (key TEXT PRIMARY KEY, json TEXT NOT NULL); INSERT INTO kv VALUES ('host', '\"sis8.pup.edu.ph\"');").unwrap();
        drop(plain);
        assert_eq!(header(&path), b"SQLite format 3\0");

        let store = Store::open(&path, &KEY).unwrap();
        assert_eq!(store.load().unwrap().host.as_deref(), Some("sis8.pup.edu.ph"));
        assert_ne!(header(&path), b"SQLite format 3\0");
        assert!(!path.with_extension("sqlite.enc").exists());
    }

    #[test]
    fn a_half_finished_migration_is_redone() {
        let path = scratch("crash");
        let plain = Connection::open(&path).unwrap();
        plain.execute_batch("CREATE TABLE kv (key TEXT PRIMARY KEY, json TEXT NOT NULL); INSERT INTO kv VALUES ('host', '\"sis8.pup.edu.ph\"');").unwrap();
        drop(plain);
        std::fs::write(path.with_extension("sqlite.enc"), b"half a file").unwrap();

        let store = Store::open(&path, &KEY).unwrap();
        assert_eq!(store.load().unwrap().host.as_deref(), Some("sis8.pup.edu.ph"));
        assert!(!path.with_extension("sqlite.enc").exists());
    }

    #[test]
    fn the_chat_keeps_sixty_turns_and_goes_with_sign_out_and_wipe() {
        let store = Store::in_memory().unwrap();
        for i in 0..70 {
            store.add_turn(if i % 2 == 0 { "me" } else { "lar" }, &format!("t{i}"), i, i > 60).unwrap();
        }
        let all = store.turns(100).unwrap();
        assert_eq!((all.len(), all[0].text.as_str(), all[59].text.as_str()), (60, "t10", "t69"));
        assert_eq!(store.turns(2).unwrap().iter().map(|t| t.text.as_str()).collect::<Vec<_>>(), ["t68", "t69"], "oldest first");
        assert!(store.turns(1).unwrap()[0].ask);
        store.forget_sis().unwrap();
        assert!(store.turns(5).unwrap().is_empty(), "LAR may have quoted grades");
        store.add_turn("me", "x", 1, false).unwrap();
        store.wipe().unwrap();
        assert!(store.turns(5).unwrap().is_empty());
    }
}
