//! The backup file (spec 047 C9, C10): what the student made, as JSON, built
//! from the data and never a copy of the store. No logins, tokens or SIS
//! snapshot. Not encrypted: the page says so before it's saved.

use crate::deadline::OwnDeadline;
use crate::grades::Goals;
use crate::notes::Note;
use crate::store::{Snapshot, Store, StoreError};
use crate::study::{Deck, Stats};
use crate::syllabus::Plan;
use crate::today::{ClassInfo, Marks};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

pub const APP: &str = "intportal";
/// Bump when the file changes shape in a way an older app can't read.
pub const VERSION: u32 = 1;
/// A real backup is far smaller; anything bigger is refused before it's read.
pub const MAX_BYTES: usize = 25 * 1024 * 1024;
/// PBKDF2 rounds for `Owner`; slow on purpose, since a student number has little entropy.
const ROUNDS: u32 = 100_000;

/// Whose file this is: a salted slow hash of the student number, never the number.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Owner {
    pub salt: String,
    pub rounds: u32,
    pub hash: String,
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// PBKDF2-HMAC-SHA256, one 32-byte block (RFC 8018), on `sha2` alone.
fn pbkdf2(password: &[u8], salt: &[u8], rounds: u32) -> [u8; 32] {
    let mut key = [0u8; 64];
    if password.len() > 64 {
        key[..32].copy_from_slice(&Sha256::digest(password));
    } else {
        key[..password.len()].copy_from_slice(password);
    }
    let (mut inner, mut outer) = (Sha256::new(), Sha256::new());
    inner.update(key.map(|b| b ^ 0x36));
    outer.update(key.map(|b| b ^ 0x5c));
    let mac = |data: &[u8]| -> [u8; 32] {
        let mut i = inner.clone();
        i.update(data);
        let mut o = outer.clone();
        o.update(i.finalize());
        o.finalize().into()
    };
    let mut u = mac(&[salt, &1u32.to_be_bytes()].concat());
    let mut t = u;
    for _ in 1..rounds {
        u = mac(&u);
        t.iter_mut().zip(u).for_each(|(a, b)| *a ^= b);
    }
    t
}

/// The student number as the app compares it: letters and digits, upper case.
fn normal(student_number: &str) -> String {
    student_number.chars().filter(|c| c.is_ascii_alphanumeric()).map(|c| c.to_ascii_uppercase()).collect()
}

impl Owner {
    fn new(student_number: &str, salt: [u8; 16]) -> Owner {
        Owner { salt: hex(&salt), rounds: ROUNDS, hash: hex(&pbkdf2(normal(student_number).as_bytes(), &salt, ROUNDS)) }
    }

    fn is(&self, student_number: &str) -> bool {
        let salt: Option<Vec<u8>> = (0..self.salt.len() / 2).map(|i| u8::from_str_radix(self.salt.get(2 * i..2 * i + 2)?, 16).ok()).collect();
        // Only the rounds this version writes: a file can't pick a cost.
        self.rounds == ROUNDS && salt.is_some_and(|s| self.hash == hex(&pbkdf2(normal(student_number).as_bytes(), &s, ROUNDS)))
    }
}

/// Just enough to tell a newer file from a damaged one.
#[derive(Deserialize)]
struct Head {
    app: Option<String>,
    version: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Backup {
    pub app: String,
    pub version: u32,
    /// Unix seconds the file was made.
    pub made: i64,
    pub student: Owner,
    pub notes: Vec<Note>,
    pub decks: Vec<Deck>,
    pub syllabus: BTreeMap<String, Plan>,
    pub goals: Goals,
    pub marks: Marks,
    pub colors: BTreeMap<String, String>,
    /// Links and descriptions by subject code (spec 030 C1).
    #[serde(default)]
    pub class_info: BTreeMap<String, ClassInfo>,
    pub own_deadlines: Vec<OwnDeadline>,
    pub done: BTreeSet<String>,
    pub study_stats: Stats,
    /// The webview's saved themes (`[{id, code}]`), handed in by the UI.
    #[serde(default)]
    pub themes: Vec<serde_json::Value>,
    /// Note photos, each with the note it belongs to (spec 046 C16).
    #[serde(default)]
    pub photos: Vec<BackupPhoto>,
}

/// One photo in the file: the JPEG (and its strip copy) as base64.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BackupPhoto {
    pub note_key: String,
    pub w: u32,
    pub h: u32,
    pub created: i64,
    pub data: String,
    #[serde(default)]
    pub thumb: Option<String>,
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
    #[error("That file is too big to be an IntPortal backup.")]
    TooBig,
    #[error("That backup is from a newer IntPortal. Update the app, then try again.")]
    Newer,
    #[error("Sign in first, then restore.")]
    SignedOut,
    #[error("That backup belongs to another student.")]
    OtherStudent,
}

impl Backup {
    /// Builds the file from the store. `student` is the signed-in student number
    /// and `salt` is 16 random bytes, new for every file.
    pub fn make(store: &Store, student: &str, salt: [u8; 16], themes: Vec<serde_json::Value>, now: i64) -> Result<Backup, StoreError> {
        let Snapshot { marks, colors, class_info, goals, syllabus, own_deadlines, done, .. } = store.load()?;
        Ok(Backup {
            app: APP.into(),
            version: VERSION,
            made: now,
            student: Owner::new(student, salt),
            notes: store.notes()?,
            decks: store.decks()?,
            syllabus,
            goals,
            marks,
            colors,
            class_info,
            own_deadlines,
            done,
            study_stats: store.study_stats()?,
            themes,
            photos: store.backup_photos()?,
        })
    }

    /// Reads a file's text. A newer version is told apart from a damaged file
    /// before the rest is read, since a newer file may have a shape this one can't.
    pub fn parse(text: &str) -> Result<Backup, BackupError> {
        if text.len() > MAX_BYTES {
            return Err(BackupError::TooBig);
        }
        let head: Head = serde_json::from_str(text).map_err(|_| BackupError::Damaged)?;
        if head.app.as_deref() != Some(APP) {
            return Err(BackupError::Damaged);
        }
        match head.version {
            Some(n) if n > u64::from(VERSION) => return Err(BackupError::Newer),
            Some(n) if n >= 1 => {}
            _ => return Err(BackupError::Damaged),
        }
        serde_json::from_str(text).map_err(|_| BackupError::Damaged)
    }

    /// Whose file this is, against the signed-in student (`None`: nobody).
    pub fn check(&self, signed_in: Option<&str>) -> Result<(), BackupError> {
        match signed_in {
            None => Err(BackupError::SignedOut),
            Some(n) if self.student.is(n) => Ok(()),
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
        snap.done.insert("own:own1".into());
        snap.done.insert("mab:7".into());
        snap.colors.insert("A".into(), "#3b82f6".into());
        snap.goals.target_gpa = Some(1.5);
        snap.class_info.insert("A".into(), ClassInfo { link: Some("https://zoom.us/j/1".into()), about: Some("Room B".into()) });
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
        serde_json::to_string(&Backup::make(s, ME, [7; 16], vec![serde_json::json!({"id": "t", "code": "x"})], 9).unwrap()).unwrap()
    }

    #[test]
    fn c9_backup_has_no_logins() {
        let s = filled();
        s.save_mabini(&crate::mabini::MabiniData { last_synced: Some(5), ..Default::default() }).unwrap();
        let text = file(&s);
        let v: serde_json::Value = serde_json::from_str(&text).unwrap();
        let keys: Vec<&str> = v.as_object().unwrap().keys().map(String::as_str).collect();
        let allowed = ["app", "class_info", "colors", "decks", "done", "goals", "made", "marks", "notes", "own_deadlines", "photos", "student", "study_stats", "syllabus", "themes", "version"];
        assert_eq!(keys, allowed, "a new field in the file has to be added here on purpose");
        for secret in [ME, "password", "birth", "token", "keychain", "sis8.pup.edu.ph", "last_synced", "sessions", "grades", "mabini"] {
            assert!(!text.to_lowercase().contains(&secret.to_lowercase()), "backup mentions {secret}");
        }
    }

    #[test]
    fn c9_backup_keeps_own_deadlines_and_done() {
        let b = Backup::parse(&file(&filled())).unwrap();
        assert_eq!((b.own_deadlines.len(), b.done.contains("own:own1")), (1, true));
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
        let mut theirs = fresh.load().unwrap();
        theirs.done.extend(["mab:9".to_string(), "own:stale".to_string()]);
        fresh.save(&theirs).unwrap();
        fresh.restore(&b).unwrap();
        let (x, y) = (a.load().unwrap(), fresh.load().unwrap());
        assert_eq!((&x.marks, &x.colors, &x.class_info, &x.goals, &x.syllabus, &x.own_deadlines), (&y.marks, &y.colors, &y.class_info, &y.goals, &y.syllabus, &y.own_deadlines));
        let done: Vec<&str> = y.done.iter().map(String::as_str).collect();
        assert_eq!(done, ["mab:9", "own:own1"], "eMabini Done marks stay, own ones come from the file");
        assert_eq!((a.notes().unwrap(), a.decks().unwrap(), a.study_stats().unwrap()), (fresh.notes().unwrap(), fresh.decks().unwrap(), fresh.study_stats().unwrap()));
        assert_eq!(y.class_info.len(), 1, "030 C1 info comes back");
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
    fn c10_oversize_file_refused_and_owner_is_salted() {
        assert_eq!(Backup::parse(&" ".repeat(MAX_BYTES + 1)), Err(BackupError::TooBig));
        let (a, b) = (Owner::new(ME, [1; 16]), Owner::new(ME, [2; 16]));
        assert_ne!(a.hash, b.hash);
        assert!(a.is(ME) && !a.is("2023-00124-MN-0"));
        // RFC 7914 section 11 vector for PBKDF2-HMAC-SHA256: ("passwd", "salt", c = 1).
        assert_eq!(hex(&pbkdf2(b"passwd", b"salt", 1))[..16], *"55ac046e56e3089f");
    }

    #[test]
    fn c10_other_students_backup_refused() {
        let b = Backup::parse(&file(&filled())).unwrap();
        assert_eq!(b.check(Some("2023-00124-MN-0")), Err(BackupError::OtherStudent));
        assert_eq!(b.check(None), Err(BackupError::SignedOut));
    }

    #[test]
    fn photos_survive_a_backup_round_trip_and_a_refused_restore_leaves_them() {
        let s = filled();
        s.set_note("note:a", "words", None, 400).unwrap();
        let p = s.add_photo("note:a", &crate::store::NewPhoto { w: 4, h: 3, bytes: &[1, 2, 3] }, None, None, 500).unwrap();
        s.set_photo_thumb(p.id, &[9]).unwrap();
        let b = Backup::parse(&file(&s)).unwrap();
        assert_eq!(b.photos.len(), s.photos("note:a").unwrap().len());
        assert_eq!(b.preview().photos, b.photos.len());
        let fresh = Store::in_memory().unwrap();
        fresh.restore(&b).unwrap();
        let got = fresh.photos("note:a").unwrap();
        assert_eq!(got.len(), b.photos.len());
        assert_eq!(fresh.photo_bytes(got.last().unwrap().id).unwrap(), [1, 2, 3]);
        assert_eq!(fresh.photo_thumb(got.last().unwrap().id).unwrap(), [9]);
        // A photo the file can't decode refuses the whole restore: nothing changes.
        let mut bad = b.clone();
        bad.photos[0].data = "!!!".into();
        let before = (fresh.photos("note:a").unwrap(), fresh.notes().unwrap());
        assert!(fresh.restore(&bad).is_err());
        assert_eq!((fresh.photos("note:a").unwrap(), fresh.notes().unwrap()), before);
        assert!(fresh.space().unwrap().photos >= 3);
    }

    #[test]
    fn c11_space_counts_notes_and_decks() {
        let sp = filled().space().unwrap();
        assert_eq!((sp.notes, sp.photos), (6, 0));
        assert!(sp.decks > 0 && sp.other > 0);
    }
}
