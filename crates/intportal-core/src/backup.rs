//! The backup file (spec 047 C9, C10): what the student made, as JSON, built
//! from the data and never a copy of the store. No logins, tokens or SIS
//! snapshot. Not encrypted: the page says so before it's saved.

use crate::deadline::OwnDeadline;
use crate::grades::Goals;
use crate::notes::Note;
use crate::store::{student_hash, Snapshot, Store, StoreError};
use crate::study::{Deck, Stats};
use crate::syllabus::Plan;
use crate::today::Marks;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

pub const APP: &str = "intportal";
/// Bump when the file changes shape in a way an older app can't read.
pub const VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Backup {
    pub app: String,
    pub version: u32,
    /// Unix seconds the file was made.
    pub made: i64,
    /// `student_hash` of the number it belongs to.
    pub student: String,
    pub notes: Vec<Note>,
    pub decks: Vec<Deck>,
    pub syllabus: BTreeMap<String, Plan>,
    pub goals: Goals,
    pub marks: Marks,
    pub colors: BTreeMap<String, String>,
    pub own_deadlines: Vec<OwnDeadline>,
    pub done: BTreeSet<String>,
    pub study_stats: Stats,
    /// The webview's saved themes (`[{id, code}]`), handed in by the UI.
    #[serde(default)]
    pub themes: Vec<serde_json::Value>,
    /// Note photos. Empty until photos are stored; restore ignores it for now.
    #[serde(default)]
    pub photos: Vec<serde_json::Value>,
}

/// What a restore would bring, for the student to read before agreeing.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Preview {
    pub made: i64,
    pub notes: usize,
    pub decks: usize,
    pub cards: usize,
    pub syllabus_pages: usize,
    pub own_deadlines: usize,
    pub themes: usize,
    pub photos: usize,
}

#[derive(Debug, PartialEq, thiserror::Error)]
pub enum BackupError {
    #[error("That file isn't a readable IntPortal backup.")]
    Damaged,
    #[error("That backup is from a newer IntPortal. Update the app, then try again.")]
    Newer,
    #[error("Sign in first, then restore.")]
    SignedOut,
    #[error("That backup belongs to another student.")]
    OtherStudent,
}

impl Backup {
    /// Builds the file from the store. `student` is the signed-in student number.
    pub fn make(store: &Store, student: &str, themes: Vec<serde_json::Value>, now: i64) -> Result<Backup, StoreError> {
        let Snapshot { marks, colors, goals, syllabus, own_deadlines, done, .. } = store.load()?;
        Ok(Backup {
            app: APP.into(),
            version: VERSION,
            made: now,
            student: student_hash(student),
            notes: store.notes()?,
            decks: store.decks()?,
            syllabus,
            goals,
            marks,
            colors,
            own_deadlines,
            done,
            study_stats: store.study_stats()?,
            themes,
            photos: vec![],
        })
    }

    /// Reads a file's text. A newer version is told apart from a damaged file
    /// before the rest is read, since a newer file may have a shape this one can't.
    pub fn parse(text: &str) -> Result<Backup, BackupError> {
        let v: serde_json::Value = serde_json::from_str(text).map_err(|_| BackupError::Damaged)?;
        if v.get("app").and_then(|a| a.as_str()) != Some(APP) {
            return Err(BackupError::Damaged);
        }
        match v.get("version").and_then(|n| n.as_u64()) {
            Some(n) if n > u64::from(VERSION) => return Err(BackupError::Newer),
            Some(n) if n >= 1 => {}
            _ => return Err(BackupError::Damaged),
        }
        serde_json::from_value(v).map_err(|_| BackupError::Damaged)
    }

    /// Whose file this is, against the signed-in student (`None`: nobody).
    pub fn check(&self, signed_in: Option<&str>) -> Result<(), BackupError> {
        match signed_in {
            None => Err(BackupError::SignedOut),
            Some(n) if student_hash(n) == self.student => Ok(()),
            Some(_) => Err(BackupError::OtherStudent),
        }
    }

    pub fn preview(&self) -> Preview {
        Preview {
            made: self.made,
            notes: self.notes.len(),
            decks: self.decks.len(),
            cards: self.decks.iter().map(|d| d.cards.len()).sum(),
            syllabus_pages: self.syllabus.len(),
            own_deadlines: self.own_deadlines.len(),
            themes: self.themes.len(),
            photos: self.photos.len(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::today::{Date, Mark};

    const ME: &str = "2023-00123-MN-0";

    fn filled() -> Store {
        let s = Store::in_memory().unwrap();
        let mut snap = Snapshot::default();
        snap.own_deadlines.push(OwnDeadline { id: "own1".into(), title: "Essay".into(), subject: Some("A".into()), kind: crate::syllabus::Kind::Project, date: Date::new(2026, 12, 1) });
        snap.done.insert("own1".into());
        snap.colors.insert("A".into(), "#3b82f6".into());
        snap.goals.target_gpa = Some(1.5);
        snap.marks.mode.set("A-1-0-60", None, Some(Mark::Online));
        snap.syllabus.insert("A".into(), Plan { target: Some(90.0), ..Default::default() });
        snap.host = Some("sis8.pup.edu.ph".into());
        snap.last_synced = Some("2026-11-01T00:00:00Z".into());
        s.save(&snap).unwrap();
        s.set_note("note:a", "Trees", Some("T"), 5).unwrap();
        s.set_note_subject("note:a", Some("A")).unwrap();
        s.set_note_pin("note:a", true).unwrap();
        s.save_deck(&Deck { id: "d".into(), name: "D".into(), subject: None, cards: vec![] }).unwrap();
        s.save_study_stats(&Stats { streak: 4, ..Default::default() }).unwrap();
        s
    }

    fn file(s: &Store) -> String {
        serde_json::to_string(&Backup::make(s, ME, vec![serde_json::json!({"id": "t", "code": "x"})], 9).unwrap()).unwrap()
    }

    #[test]
    fn c9_backup_has_no_logins() {
        let s = filled();
        s.save_mabini(&crate::mabini::MabiniData { last_synced: Some(5), ..Default::default() }).unwrap();
        let text = file(&s);
        for secret in [ME, "password", "birth", "token", "keychain", "sis8.pup.edu.ph", "last_synced", "sessions", "grades", "mabini"] {
            assert!(!text.to_lowercase().contains(&secret.to_lowercase()), "backup mentions {secret}");
        }
    }

    #[test]
    fn c9_backup_keeps_own_deadlines_and_done() {
        let b = Backup::parse(&file(&filled())).unwrap();
        assert_eq!((b.own_deadlines.len(), b.done.contains("own1")), (1, true));
        assert_eq!((b.notes[0].subject.as_deref(), b.notes[0].pinned), (Some("A"), true));
        assert_eq!(b.study_stats.streak, 4);
        assert_eq!(b.photos.len(), 0);
    }

    #[test]
    fn c10_round_trip() {
        let a = filled();
        let b = Backup::parse(&file(&a)).unwrap();
        b.check(Some(" 2023-00123-mn-0 ")).unwrap();
        let fresh = Store::in_memory().unwrap();
        fresh.set_note("note:old", "gone", None, 1).unwrap();
        fresh.restore(&b).unwrap();
        let (x, y) = (a.load().unwrap(), fresh.load().unwrap());
        assert_eq!((&x.marks, &x.colors, &x.goals, &x.syllabus, &x.own_deadlines, &x.done), (&y.marks, &y.colors, &y.goals, &y.syllabus, &y.own_deadlines, &y.done));
        assert_eq!((a.notes().unwrap(), a.decks().unwrap(), a.study_stats().unwrap()), (fresh.notes().unwrap(), fresh.decks().unwrap(), fresh.study_stats().unwrap()));
        assert_eq!(y.host, None, "SIS data isn't restored");
        assert_eq!(b.preview().notes, 1);
        assert_eq!(b.preview().themes, 1);
    }

    #[test]
    fn c10_newer_version_refused() {
        let text = file(&filled()).replacen("\"version\":1", "\"version\":2", 1);
        assert_eq!(Backup::parse(&text), Err(BackupError::Newer));
        assert_eq!(Backup::parse(r#"{"app":"intportal","version":2,"future":true}"#), Err(BackupError::Newer));
    }

    #[test]
    fn c10_bad_backup_changes_nothing() {
        let s = filled();
        let before = (s.load().unwrap(), s.notes().unwrap(), s.decks().unwrap());
        let good = file(&s);
        for bad in [good[..good.len() / 2].to_string(), "not json".into(), r#"{"app":"other","version":1}"#.into(), good.replace("\"notes\":[", "\"notes\":{")] {
            assert_eq!(Backup::parse(&bad), Err(BackupError::Damaged));
        }
        // A restore that fails part way (a duplicate note key) rolls back whole.
        let mut dup = Backup::parse(&good).unwrap();
        dup.notes.push(dup.notes[0].clone());
        dup.colors.clear();
        assert!(s.restore(&dup).is_err());
        assert_eq!(before, (s.load().unwrap(), s.notes().unwrap(), s.decks().unwrap()));
    }

    #[test]
    fn c10_other_students_backup_refused() {
        let b = Backup::parse(&file(&filled())).unwrap();
        assert_eq!(b.check(Some("2023-00124-MN-0")), Err(BackupError::OtherStudent));
        assert_eq!(b.check(None), Err(BackupError::SignedOut));
    }

    #[test]
    fn c11_space_counts_notes_and_decks() {
        let sp = filled().space().unwrap();
        assert_eq!((sp.notes, sp.photos), (6, 0));
        assert!(sp.decks > 0 && sp.other > 0);
    }
}
