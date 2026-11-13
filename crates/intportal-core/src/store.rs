//! Everything the app keeps on the device, in one SQLite file (ADR-0002),
//! encrypted with SQLCipher under a key the shell keeps in the keychain.
//! One JSON value per key: the data is small and read whole.

use crate::backup::Backup;
use crate::grades::{GradeReport, Goals};
use crate::model::ClassSession;
use crate::notes::Note;
use crate::study::{Deck, Stats};
use crate::syllabus::Plan;
use crate::today::{ClassInfo, Marks};
use base64::{engine::general_purpose::STANDARD as B64, Engine};
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
    /// What the student wrote about a class, by subject code (spec 030 C1).
    #[serde(default)]
    pub class_info: BTreeMap<String, ClassInfo>,
    /// The host that last proved good, tried first next time.
    pub host: Option<String>,
    /// RFC 3339, written by the shell.
    pub last_synced: Option<String>,
    /// Deadlines the student added (spec 041).
    #[serde(default)]
    pub own_deadlines: Vec<crate::deadline::OwnDeadline>,
    /// Deadline ids marked done on this phone: eMabini and own ones (041 C5).
    #[serde(default)]
    pub done: std::collections::BTreeSet<String>,
}

/// The file one student's data lives in. Each student number gets its own,
/// so a second student signing in on the same phone never sees (or wipes)
/// the first one's notes. The name hides the number (FNV-1a), it doesn't
/// protect it; the store's own encryption does that.
pub fn account_file(student_number: &str) -> String {
    format!("account-{}.sqlite", student_hash(student_number))
}

/// The same hash on its own, what a backup file carries to say whose it is.
fn student_hash(student_number: &str) -> String {
    let key: String = student_number.chars().filter(|c| c.is_ascii_alphanumeric()).map(|c| c.to_ascii_uppercase()).collect();
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in key.bytes() {
        h = (h ^ u64::from(b)).wrapping_mul(0x100_0000_01b3);
    }
    format!("{h:016x}")
}

/// Bytes by kind, for Backup and data. The AI model's file isn't here: it has its own card.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize)]
pub struct Space {
    pub notes: u64,
    pub photos: u64,
    pub decks: u64,
    /// Schedule, grades, syllabus pages, search index, chat and the rest.
    pub other: u64,
}

/// One message of the LAR chat.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Turn {
    pub role: String,
    pub text: String,
    pub at: i64,
    pub ask: bool,
}

/// Something the AI can search: a note, a deck's cards or a subject's syllabus.
/// `key` is `note:`/`class:`/`day:` for notes, `card:<deck id>` or `plan:<code>`.
/// `stamp` changes when the text does: a note's edit time, else a hash of the text.
#[derive(Debug, Clone, PartialEq)]
pub struct Source {
    pub key: String,
    pub title: String,
    pub text: String,
    pub stamp: i64,
}

/// FNV-1a, as a change marker for text that has no edit time.
fn stamp_of(text: &str) -> i64 {
    text.bytes().fold(0xcbf2_9ce4_8422_2325_u64, |h, b| (h ^ u64::from(b)).wrapping_mul(0x100_0000_01b3)) as i64
}

pub struct Store {
    db: Connection,
}

/// A note holds at most this many photos (046 C15a).
pub const MAX_PHOTOS: i64 = 20;

/// A photo on its way in.
pub struct NewPhoto<'a> {
    pub w: u32,
    pub h: u32,
    pub bytes: &'a [u8],
}

/// One photo's row, without its bytes.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Photo {
    pub id: i64,
    pub w: u32,
    pub h: u32,
    pub created: i64,
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
    #[error("That note isn't saved yet.")]
    NoSuchNote,
    #[error("Only a freeform note can change subject.")]
    SubjectIsFixed,
    #[error("A note holds up to 20 photos.")]
    TooManyPhotos,
}

/// `CREATE TABLE IF NOT EXISTS` leaves a store's existing table alone, so
/// columns added later are added here. A blind ALTER fails on the second open,
/// so each is checked first. A failure is an ordinary error, never `Locked`:
/// the shell moves a Locked store aside, which would look like a wipe.
fn add_note_columns(db: &Connection) -> rusqlite::Result<()> {
    let have: Vec<String> = db.prepare("PRAGMA table_info(notes)")?.query_map([], |r| r.get(1))?.collect::<Result<_, _>>()?;
    for (name, column) in [("subject", "subject TEXT"), ("pinned", "pinned INTEGER NOT NULL DEFAULT 0")] {
        if !have.iter().any(|h| h == name) {
            db.execute_batch(&format!("ALTER TABLE notes ADD COLUMN {column};"))?;
        }
    }
    Ok(())
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
             CREATE TABLE IF NOT EXISTS turns (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, text TEXT NOT NULL, at INTEGER NOT NULL, ask INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS photos (id INTEGER PRIMARY KEY AUTOINCREMENT, note_key TEXT NOT NULL, w INTEGER NOT NULL, h INTEGER NOT NULL, created INTEGER NOT NULL, bytes BLOB NOT NULL, thumb BLOB);
             CREATE INDEX IF NOT EXISTS photos_note ON photos (note_key);",
        )?;
        add_note_columns(&db)?;
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
            class_info: self.get("class_info")?.unwrap_or_default(),
            syllabus: self.get("syllabus")?.unwrap_or_default(),
            host: self.get::<Option<_>>("host")?.flatten(),
            last_synced: self.get::<Option<_>>("last_synced")?.flatten(),
            own_deadlines: self.get("own_deadlines")?.unwrap_or_default(),
            done: self.get("done")?.unwrap_or_default(),
        })
    }

    pub fn save(&self, s: &Snapshot) -> Result<(), StoreError> {
        self.put("sessions", &s.sessions)?;
        self.put("grades", &s.grades)?;
        self.put("history", &s.history)?;
        self.put("marks", &s.marks)?;
        self.put("colors", &s.colors)?;
        self.put("goals", &s.goals)?;
        self.put("class_info", &s.class_info)?;
        self.put("syllabus", &s.syllabus)?;
        self.put("host", &s.host)?;
        self.put("own_deadlines", &s.own_deadlines)?;
        self.put("done", &s.done)?;
        self.put("last_synced", &s.last_synced)
    }

    /// Every note, the latest edit first.
    pub fn notes(&self) -> Result<Vec<Note>, StoreError> {
        let mut q = self.db.prepare("SELECT key, text, title, updated, subject, pinned, (SELECT COUNT(*) FROM photos WHERE note_key = key) FROM notes ORDER BY updated DESC, key")?;
        let rows = q.query_map([], |r| Ok(Note { key: r.get(0)?, text: r.get(1)?, title: r.get(2)?, updated: r.get(3)?, subject: r.get(4)?, pinned: r.get(5)?, photos: r.get(6)? }))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Saves one note. Blank text deletes it, so an emptied note doesn't
    /// linger in the list, unless it has photos: then the row stays with no
    /// text and no AI chunks (046 C17c). `title` empty keeps the one already stored.
    pub fn set_note(&self, key: &str, text: &str, title: Option<&str>, now: i64) -> Result<(), StoreError> {
        if text.trim().is_empty() {
            let tx = self.db.unchecked_transaction()?;
            let photos: i64 = tx.query_row("SELECT COUNT(*) FROM photos WHERE note_key = ?1", [key], |r| r.get(0))?;
            if photos > 0 {
                tx.execute("UPDATE notes SET text = '', updated = ?2 WHERE key = ?1", params![key, now])?;
            } else {
                tx.execute("DELETE FROM notes WHERE key = ?1", [key])?;
            }
            tx.execute("DELETE FROM chunks WHERE note_key = ?1", [key])?;
            tx.commit()?;
        } else {
            self.db.execute(
                "INSERT INTO notes (key, text, title, updated) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(key) DO UPDATE SET text = excluded.text, title = COALESCE(excluded.title, notes.title), updated = excluded.updated",
                params![key, text, title, now],
            )?;
        }
        Ok(())
    }

    /// Deletes a note with its chunks and photos, in one transaction (046 C17).
    pub fn delete_note(&self, key: &str) -> Result<(), StoreError> {
        let tx = self.db.unchecked_transaction()?;
        for table in ["notes WHERE key", "chunks WHERE note_key", "photos WHERE note_key"] {
            tx.execute(&format!("DELETE FROM {table} = ?1"), [key])?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Adds a photo. A note with no row gets one, with no text and `title`, in
    /// the same transaction (C17c), and `subject` files a freeform note (the
    /// held one); either way it moves up its subject (C15a). The 21st photo is refused.
    pub fn add_photo(&self, key: &str, photo: &NewPhoto, title: Option<&str>, subject: Option<&str>, now: i64) -> Result<Photo, StoreError> {
        let tx = self.db.unchecked_transaction()?;
        let have: i64 = tx.query_row("SELECT COUNT(*) FROM photos WHERE note_key = ?1", [key], |r| r.get(0))?;
        if have >= MAX_PHOTOS {
            return Err(StoreError::TooManyPhotos);
        }
        tx.execute(
            "INSERT INTO notes (key, text, title, updated) VALUES (?1, '', ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET title = COALESCE(excluded.title, notes.title), updated = excluded.updated",
            params![key, title, now],
        )?;
        if let (true, Some(code)) = (key.starts_with("note:"), subject.map(str::trim).filter(|s| !s.is_empty())) {
            tx.execute("UPDATE notes SET subject = ?2 WHERE key = ?1", params![key, code])?;
        }
        tx.execute("INSERT INTO photos (note_key, w, h, created, bytes) VALUES (?1, ?2, ?3, ?4, ?5)", params![key, photo.w, photo.h, now, photo.bytes])?;
        let id = tx.last_insert_rowid();
        tx.commit()?;
        Ok(Photo { id, w: photo.w, h: photo.h, created: now })
    }

    /// Keeps a small copy for the strip, so it never loads full photos.
    pub fn set_photo_thumb(&self, id: i64, thumb: &[u8]) -> Result<(), StoreError> {
        self.db.execute("UPDATE photos SET thumb = ?2 WHERE id = ?1", params![id, thumb])?;
        Ok(())
    }

    /// The strip's copy, or the photo itself when it has none yet.
    pub fn photo_thumb(&self, id: i64) -> Result<Vec<u8>, StoreError> {
        Ok(self.db.query_row("SELECT COALESCE(thumb, bytes) FROM photos WHERE id = ?1", [id], |r| r.get(0))?)
    }

    /// A note's photos, oldest first. Never reads the bytes.
    pub fn photos(&self, key: &str) -> Result<Vec<Photo>, StoreError> {
        let mut q = self.db.prepare("SELECT id, w, h, created FROM photos WHERE note_key = ?1 ORDER BY id")?;
        let rows = q.query_map([key], |r| Ok(Photo { id: r.get(0)?, w: r.get(1)?, h: r.get(2)?, created: r.get(3)? }))?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn photo_bytes(&self, id: i64) -> Result<Vec<u8>, StoreError> {
        Ok(self.db.query_row("SELECT bytes FROM photos WHERE id = ?1", [id], |r| r.get(0))?)
    }

    /// Every photo for a backup file. ponytail: all in memory at once (at most 20 per note);
    /// stream per photo if backups grow past the file cap.
    pub fn backup_photos(&self) -> Result<Vec<crate::backup::BackupPhoto>, StoreError> {
        let mut q = self.db.prepare("SELECT note_key, w, h, created, bytes, thumb FROM photos ORDER BY id")?;
        let rows = q.query_map([], |r| {
            Ok(crate::backup::BackupPhoto {
                note_key: r.get(0)?,
                w: r.get(1)?,
                h: r.get(2)?,
                created: r.get(3)?,
                data: B64.encode(r.get::<_, Vec<u8>>(4)?),
                thumb: r.get::<_, Option<Vec<u8>>>(5)?.map(|t| B64.encode(t)),
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Removes one photo. A note left with no photos and no text goes too, with
    /// its chunks, in the same transaction.
    pub fn delete_photo(&self, id: i64) -> Result<(), StoreError> {
        let tx = self.db.unchecked_transaction()?;
        let key: Option<String> = tx.query_row("SELECT note_key FROM photos WHERE id = ?1", [id], |r| r.get(0)).optional()?;
        tx.execute("DELETE FROM photos WHERE id = ?1", [id])?;
        if let Some(key) = key {
            tx.execute(
                "DELETE FROM notes WHERE key = ?1 AND TRIM(text) = '' AND NOT EXISTS (SELECT 1 FROM photos WHERE note_key = ?1)",
                [&key],
            )?;
            tx.execute("DELETE FROM chunks WHERE note_key = ?1 AND NOT EXISTS (SELECT 1 FROM notes WHERE key = ?1)", [&key])?;
        }
        tx.commit()?;
        Ok(())
    }

    /// The note (if any) and its photos as a `.zip`: `notes.md`, and each
    /// photo under `photos/` named for its note (046 C17). `key` empty: every note.
    pub fn export_zip(&self, key: Option<&str>) -> Result<Vec<u8>, StoreError> {
        use std::io::Write;
        let mut list = self.notes()?;
        if let Some(k) = key {
            list.retain(|n| n.key == k);
        }
        let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
        let opts = zip::write::SimpleFileOptions::default();
        let zerr = |e: zip::result::ZipError| StoreError::Io(std::io::Error::other(e));
        zip.start_file("notes.md", opts).map_err(zerr)?;
        zip.write_all(crate::notes::markdown(&list).as_bytes())?;
        for n in &list {
            let name: String = crate::notes::heading(n).chars().map(|c| if c.is_alphanumeric() || c == ' ' || c == '-' { c } else { '_' }).collect();
            for (i, p) in self.photos(&n.key)?.iter().enumerate() {
                zip.start_file(format!("photos/{} {}.jpg", name.trim(), i + 1), opts).map_err(zerr)?;
                zip.write_all(&self.photo_bytes(p.id)?)?;
            }
        }
        Ok(zip.finish().map_err(zerr)?.into_inner())
    }

    /// Pins or unpins a note. Not an edit: `updated` stays, so the note neither
    /// moves in its list nor goes stale for the AI.
    pub fn set_note_pin(&self, key: &str, pinned: bool) -> Result<(), StoreError> {
        match self.db.execute("UPDATE notes SET pinned = ?2 WHERE key = ?1", params![key, pinned])? {
            0 => Err(StoreError::NoSuchNote),
            _ => Ok(()),
        }
    }

    /// Files a freeform note under a subject, or under none. Not an edit, like
    /// a pin. A class note's subject is its key, and a day note has none.
    pub fn set_note_subject(&self, key: &str, subject: Option<&str>) -> Result<(), StoreError> {
        if !key.starts_with("note:") {
            return Err(StoreError::SubjectIsFixed);
        }
        let subject = subject.map(str::trim).filter(|s| !s.is_empty());
        match self.db.execute("UPDATE notes SET subject = ?2 WHERE key = ?1", params![key, subject])? {
            0 => Err(StoreError::NoSuchNote),
            _ => Ok(()),
        }
    }

    /// Replaces a note's chunks with `chunks` (text and unit vector each).
    pub fn replace_chunks(&self, note_key: &str, note_updated: i64, model: &str, chunks: &[(String, Vec<f32>)]) -> Result<(), StoreError> {
        let tx = self.db.unchecked_transaction()?;
        tx.execute("DELETE FROM chunks WHERE note_key = ?1", [note_key])?;
        // A note edited or emptied while it was embedded keeps no chunks of its old words.
        let current = !crate::notes::is_known_key(note_key)
            || tx.query_row("SELECT EXISTS (SELECT 1 FROM notes WHERE key = ?1 AND updated = ?2)", params![note_key, note_updated], |r| r.get::<_, bool>(0))?;
        if current {
            for (n, (text, vec)) in chunks.iter().enumerate() {
                let blob: Vec<u8> = vec.iter().flat_map(|f| f.to_le_bytes()).collect();
                tx.execute(
                    "INSERT INTO chunks (note_key, n, text, vec, note_updated, model) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![note_key, n as i64, text, blob, note_updated, model],
                )?;
            }
        }
        tx.commit()?;
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

    /// Everything searchable right now, notes first. A deck without cards or a
    /// plan without items has nothing to say and is left out.
    pub fn sources(&self) -> Result<Vec<Source>, StoreError> {
        let mut out: Vec<Source> = self
            .notes()?
            .into_iter()
            .filter(|n| !n.text.trim().is_empty())
            .map(|n| Source { title: crate::notes::heading(&n), key: n.key, text: n.text, stamp: n.updated })
            .collect();
        for d in self.decks()? {
            let cards = d.cards.iter().map(|c| format!("{}: {}", c.front.trim(), c.back.trim()));
            let text = std::iter::once(d.name.clone()).chain(cards).collect::<Vec<_>>().join("\n\n");
            if !d.cards.is_empty() {
                out.push(Source { key: format!("card:{}", d.id), title: format!("Cards · {}", d.name), stamp: stamp_of(&text), text });
            }
        }
        for (code, plan) in self.get::<BTreeMap<String, Plan>>("syllabus")?.unwrap_or_default() {
            let items = plan.items.iter().map(|i| {
                let when = match (i.week, i.date) {
                    (Some(w), _) => format!("Week {w} · "),
                    (None, Some(d)) => format!("{d} · "),
                    _ => String::new(),
                };
                format!("{when}{:?}: {}", i.kind, i.topic.trim())
            });
            let grading = plan.grading.iter().map(|c| format!("Grading: {} {}%", c.name.trim(), c.weight));
            let lines: Vec<String> = items.chain(grading).collect();
            if !lines.is_empty() {
                let text = format!("{code} syllabus\n\n{}", lines.join("\n\n"));
                out.push(Source { key: format!("plan:{code}"), title: format!("Syllabus · {code}"), stamp: stamp_of(&text), text });
            }
        }
        Ok(out)
    }

    /// Sources with no chunks from `model` at their current stamp. The AI embeds
    /// these just before a search; nothing here embeds.
    pub fn stale_sources(&self, model: &str) -> Result<Vec<Source>, StoreError> {
        let mut q = self.db.prepare("SELECT DISTINCT note_key, note_updated FROM chunks WHERE model = ?1")?;
        let have: std::collections::HashSet<(String, i64)> =
            q.query_map([model], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<Result<_, _>>()?;
        Ok(self.sources()?.into_iter().filter(|s| !have.contains(&(s.key.clone(), s.stamp))).collect())
    }

    /// Drops chunks whose source is gone (a deleted deck, a cleared plan).
    pub fn prune_chunks(&self) -> Result<(), StoreError> {
        let keys: std::collections::HashSet<String> = self.sources()?.into_iter().map(|s| s.key).collect();
        let mut q = self.db.prepare("SELECT DISTINCT note_key FROM chunks")?;
        let gone: Vec<String> = q.query_map([], |r| r.get(0))?.collect::<Result<Vec<String>, _>>()?.into_iter().filter(|k| !keys.contains(k)).collect();
        for k in gone {
            self.db.execute("DELETE FROM chunks WHERE note_key = ?1", [k])?;
        }
        Ok(())
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
        self.db.execute("DELETE FROM chunks WHERE note_key = ?1", [format!("card:{id}")])?;
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

    /// Replaces what a backup carries with the file's, all or nothing (spec 047 C10).
    /// SIS data, eMabini data, logins and chat stay as they are. AI chunks go,
    /// because the notes they came from just changed; search re-reads them.
    pub fn restore(&self, b: &Backup) -> Result<(), StoreError> {
        let tx = self.db.unchecked_transaction()?;
        tx.execute_batch("DELETE FROM notes; DELETE FROM decks; DELETE FROM chunks;")?;
        for n in &b.notes {
            tx.execute(
                "INSERT INTO notes (key, text, title, updated, subject, pinned) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![n.key, n.text, n.title, n.updated, n.subject, n.pinned],
            )?;
        }
        // Photos follow the notes they belong to, in the same transaction.
        tx.execute("DELETE FROM photos", [])?;
        for p in b.photos.iter().filter(|p| b.notes.iter().any(|n| n.key == p.note_key)) {
            let bad = |_| StoreError::Io(std::io::Error::other("bad photo"));
            let bytes = B64.decode(&p.data).map_err(bad)?;
            let thumb = p.thumb.as_deref().map(|t| B64.decode(t)).transpose().map_err(bad)?;
            tx.execute(
                "INSERT INTO photos (note_key, w, h, created, bytes, thumb) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![p.note_key, p.w, p.h, p.created, bytes, thumb],
            )?;
        }
        for d in &b.decks {
            tx.execute("INSERT INTO decks (id, json) VALUES (?1, ?2)", params![d.id, serde_json::to_string(d)?])?;
        }
        // eMabini's Done marks (`mab:`) belong to this phone's sync; only own ones come from the file.
        let mut done: std::collections::BTreeSet<String> = tx
            .query_row("SELECT json FROM kv WHERE key = 'done'", [], |r| r.get::<_, String>(0))
            .optional()?
            .map(|j| serde_json::from_str(&j))
            .transpose()?
            .unwrap_or_default();
        done.retain(|id| !id.starts_with("own:"));
        done.extend(b.done.iter().filter(|id| id.starts_with("own:")).cloned());
        // Links are checked again here: a hand-edited file must not smuggle one in.
        let class_info = b
            .class_info
            .as_ref()
            .map(|m| {
                m.iter()
                    .map(|(k, i)| ClassInfo::clean(i.link.clone(), i.about.clone()).map(|i| (k.clone(), i)).map_err(|e| StoreError::Io(std::io::Error::other(e))))
                    .filter(|r| r.as_ref().map_or(true, |(_, i)| !i.is_empty()))
                    .collect::<Result<BTreeMap<_, _>, _>>()
            })
            .transpose()?;
        let mut kv: Vec<(&str, String)> = vec![
            ("marks", serde_json::to_string(&b.marks)?),
            ("colors", serde_json::to_string(&b.colors)?),
            ("goals", serde_json::to_string(&b.goals)?),
            ("syllabus", serde_json::to_string(&b.syllabus)?),
            ("own_deadlines", serde_json::to_string(&b.own_deadlines)?),
            ("done", serde_json::to_string(&done)?),
            ("study_stats", serde_json::to_string(&b.study_stats)?),
        ];
        if let Some(c) = class_info {
            kv.push(("class_info", serde_json::to_string(&c)?));
        }
        for (k, json) in kv {
            tx.execute("INSERT INTO kv (key, json) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET json = excluded.json", params![k, json])?;
        }
        Ok(tx.commit()?)
    }

    /// Bytes the student's own things take, for Backup and data (C11).
    pub fn space(&self) -> Result<Space, StoreError> {
        let sum = |sql: &str| -> Result<u64, StoreError> { Ok(self.db.query_row(sql, [], |r| r.get::<_, i64>(0))?.max(0) as u64) };
        let notes = sum("SELECT COALESCE(SUM(length(CAST(text AS BLOB)) + length(CAST(COALESCE(title, '') AS BLOB))), 0) FROM notes")?;
        let decks = sum("SELECT COALESCE(SUM(length(CAST(json AS BLOB))), 0) FROM decks")?;
        let other = sum("SELECT COALESCE(SUM(length(CAST(json AS BLOB))), 0) FROM kv")?
            + sum("SELECT COALESCE(SUM(length(CAST(text AS BLOB)) + length(vec)), 0) FROM chunks")?
            + sum("SELECT COALESCE(SUM(length(CAST(text AS BLOB))), 0) FROM turns")?;
        let photos = sum("SELECT COALESCE(SUM(length(bytes) + COALESCE(length(thumb), 0)), 0) FROM photos")?;
        Ok(Space { notes, photos, decks, other })
    }

    /// Erase everything on the device, the student's own work included.
    pub fn wipe(&self) -> Result<(), StoreError> {
        let tx = self.db.unchecked_transaction()?;
        tx.execute_batch("DELETE FROM kv; DELETE FROM notes; DELETE FROM decks; DELETE FROM chunks; DELETE FROM turns; DELETE FROM photos;")?;
        tx.commit()?;
        // Deleting doesn't shrink the file; erasing everything does (046 Data).
        self.db.execute_batch("VACUUM")?;
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
    fn c1_class_info_survives_sync() {
        let store = Store::in_memory().unwrap();
        let mut snap = Snapshot::default();
        snap.class_info.insert("COMP 20073".into(), ClassInfo { link: Some("https://meet.google.com/x".into()), about: Some("Room B".into()) });
        store.save(&snap).unwrap();
        // A sync rewrites sessions and grades on the loaded snapshot.
        let mut synced = store.load().unwrap();
        synced.sessions.clear();
        synced.last_synced = Some("2".into());
        store.save(&synced).unwrap();
        assert_eq!(store.load().unwrap().class_info, snap.class_info);
        // Sign-out forgets SIS data only; Erase everything removes it.
        store.forget_sis().unwrap();
        assert_eq!(store.load().unwrap().class_info, snap.class_info);
        store.wipe().unwrap();
        assert!(store.load().unwrap().class_info.is_empty());
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
    fn c8_delete_note_drops_chunks() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "Trees are graphs", None, 100).unwrap();
        store.replace_chunks("note:a", 100, "m", &[("Trees are graphs".into(), vec![1.0, 0.0])]).unwrap();
        assert_eq!(store.chunks("m").unwrap().len(), 1);
        store.set_note("note:a", "", None, 200).unwrap();
        assert!(store.notes().unwrap().is_empty());
        assert!(store.chunks("m").unwrap().is_empty(), "spec 040 C8: the AI can't quote a deleted note");
    }

    const OLD_NOTES: &str = "CREATE TABLE notes (key TEXT PRIMARY KEY, text TEXT NOT NULL, title TEXT, updated INTEGER NOT NULL);";

    fn temp_store(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("intportal-store-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("store.db")
    }

    #[test]
    fn old_schema_opens_and_gains_columns() {
        let path = temp_store("old");
        let db = Connection::open(&path).unwrap();
        db.execute_batch(OLD_NOTES).unwrap();
        db.execute("INSERT INTO notes (key, text, title, updated) VALUES ('note:a', 'Trees', 'Ideas', 100)", []).unwrap();
        drop(db);

        let store = Store::open_plain(&path).unwrap();
        let notes = store.notes().unwrap();
        assert_eq!((notes[0].text.as_str(), notes[0].updated, notes[0].subject.as_deref(), notes[0].pinned), ("Trees", 100, None, false));
        store.set_note_pin("note:a", true).unwrap();
        drop(store);

        let store = Store::open_plain(&path).unwrap();
        assert!(store.notes().unwrap()[0].pinned, "a second open changes nothing");
        drop(store);

        // A crash between the two ALTERs leaves one column: the next open adds the other.
        let path = temp_store("half");
        let db = Connection::open(&path).unwrap();
        db.execute_batch(OLD_NOTES).unwrap();
        db.execute_batch("ALTER TABLE notes ADD COLUMN subject TEXT;").unwrap();
        drop(db);
        let store = Store::open_plain(&path).unwrap();
        assert!(store.notes().unwrap().is_empty());
    }

    #[test]
    fn migration_error_is_not_locked() {
        // A view named `notes` can't take a new column, so the migration fails.
        for (name, encrypted) in [("plain", false), ("encrypted", true)] {
            let path = temp_store(&format!("broken-{name}"));
            let db = Connection::open(&path).unwrap();
            db.execute_batch("CREATE VIEW notes AS SELECT 1 AS key;").unwrap();
            drop(db);
            let result = if encrypted { Store::open(&path, &[7; 32]) } else { Store::open_plain(&path) };
            let error = result.err().expect("the migration fails");
            assert!(!matches!(error, StoreError::Locked), "{name}: the shell would move the store aside");
            assert!(path.exists(), "{name}: the store stays where it is");
        }
    }

    #[test]
    fn pin_and_subject_keep_updated() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "alpha", None, 100).unwrap();
        store.set_note("note:b", "beta", None, 200).unwrap();
        store.replace_chunks("note:a", 100, "m", &[("alpha".into(), vec![1.0])]).unwrap();

        store.set_note_pin("note:a", true).unwrap();
        store.set_note_subject("note:a", Some("MATH 1")).unwrap();
        let notes = store.notes().unwrap();
        assert_eq!(notes.iter().map(|n| n.key.as_str()).collect::<Vec<_>>(), ["note:b", "note:a"], "no jump in the list");
        assert_eq!((notes[1].updated, notes[1].pinned, notes[1].subject.as_deref()), (100, true, Some("MATH 1")));
        assert_eq!(store.stale_sources("m").unwrap().iter().map(|s| s.key.as_str()).collect::<Vec<_>>(), ["note:b"], "still fresh for the AI");

        store.set_note_subject("note:a", Some("  ")).unwrap();
        assert_eq!(store.notes().unwrap()[1].subject, None, "blank means General");
        store.set_note_subject("note:a", Some("MATH 1")).unwrap();
        store.set_note_subject("note:a", None).unwrap();
        assert_eq!(store.notes().unwrap()[1].subject, None);
        store.set_note_pin("note:a", false).unwrap();
        assert!(!store.notes().unwrap()[1].pinned);
    }

    #[test]
    fn autosave_does_not_touch_pin_or_subject() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "alpha", Some("Name"), 100).unwrap();
        store.set_note_pin("note:a", true).unwrap();
        store.set_note_subject("note:a", Some("MATH 1")).unwrap();
        store.set_note("note:a", "alpha beta", None, 200).unwrap();
        let note = &store.notes().unwrap()[0];
        assert_eq!((note.text.as_str(), note.updated, note.pinned, note.subject.as_deref()), ("alpha beta", 200, true, Some("MATH 1")));
    }

    #[test]
    fn meta_on_missing_key_errors() {
        let store = Store::in_memory().unwrap();
        assert!(matches!(store.set_note_pin("note:gone", true), Err(StoreError::NoSuchNote)));
        assert!(matches!(store.set_note_subject("note:gone", Some("MATH 1")), Err(StoreError::NoSuchNote)));
        assert!(store.notes().unwrap().is_empty(), "never creates a row");
    }

    #[test]
    fn subject_refused_on_class_and_day() {
        let store = Store::in_memory().unwrap();
        store.set_note("class:MATH 1", "x", None, 100).unwrap();
        store.set_note("day:2026-09-28", "y", None, 100).unwrap();
        assert!(matches!(store.set_note_subject("class:MATH 1", Some("COMP 2")), Err(StoreError::SubjectIsFixed)));
        assert!(matches!(store.set_note_subject("day:2026-09-28", Some("COMP 2")), Err(StoreError::SubjectIsFixed)));
        store.set_note_pin("class:MATH 1", true).unwrap();
        store.set_note_pin("day:2026-09-28", true).unwrap();
        assert!(store.notes().unwrap().iter().all(|n| n.pinned && n.subject.is_none()), "any note can be pinned");
    }

    #[test]
    fn pin_and_subject_leave_with_the_note_and_outlast_sign_out() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "alpha", None, 100).unwrap();
        store.set_note_pin("note:a", true).unwrap();
        store.set_note_subject("note:a", Some("MATH 1")).unwrap();

        store.forget_sis().unwrap();
        let note = &store.notes().unwrap()[0];
        assert_eq!((note.pinned, note.subject.as_deref()), (true, Some("MATH 1")), "sign-out keeps them");

        store.set_note("note:a", "", None, 200).unwrap();
        store.set_note("note:a", "again", None, 300).unwrap();
        let note = &store.notes().unwrap()[0];
        assert_eq!((note.pinned, note.subject.as_deref()), (false, None), "they go with a deleted note");

        store.set_note_pin("note:a", true).unwrap();
        store.wipe().unwrap();
        assert!(store.notes().unwrap().is_empty(), "Erase everything removes them");
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
        assert_eq!(store.stale_sources("m1").unwrap().len(), 2);
        store.replace_chunks("note:a", 100, "m1", &[("alpha".into(), vec![1.0, 0.0]), ("al".into(), vec![0.0, 1.0])]).unwrap();
        assert_eq!(store.stale_sources("m1").unwrap().iter().map(|n| n.key.as_str()).collect::<Vec<_>>(), ["note:b"]);
        assert_eq!(store.stale_sources("m2").unwrap().len(), 2, "another model's vectors are not reusable");
        assert_eq!(store.chunks("m1").unwrap(), [("note:a".to_string(), "alpha".to_string(), vec![1.0, 0.0]), ("note:a".to_string(), "al".to_string(), vec![0.0, 1.0])]);
        store.set_note("note:a", "alpha edited", None, 200).unwrap();
        assert_eq!(store.stale_sources("m1").unwrap().len(), 2, "an edit makes the note stale");
        store.replace_chunks("note:a", 200, "m1", &[("x".into(), vec![1.0, 0.0])]).unwrap();
        assert_eq!(store.chunks("m1").unwrap().len(), 1, "replace drops the old chunks");
        store.set_note("note:a", "", None, 300).unwrap();
        assert!(store.chunks("m1").unwrap().is_empty(), "deleting a note drops its chunks");
        store.replace_chunks("note:b", 100, "m1", &[("beta".into(), vec![1.0])]).unwrap();
        store.wipe().unwrap();
        assert!(store.chunks("m1").unwrap().is_empty());
    }

    fn deck(id: &str, name: &str, cards: &[(&str, &str)]) -> Deck {
        use crate::study::{Card, Memory};
        let cards = cards.iter().map(|(f, b)| Card { id: String::new(), front: f.to_string(), back: b.to_string(), accepted: vec![], memory: Memory::new(0) }).collect();
        Deck { id: id.into(), name: name.into(), subject: None, cards }
    }

    fn plan(topic: &str) -> Plan {
        use crate::syllabus::{Component, Item, Kind};
        Plan {
            items: vec![Item { id: "1".into(), topic: topic.into(), kind: Kind::Quiz, week: Some(3), date: None, done: false }],
            grading: vec![Component { name: "Midterm".into(), weight: 30.0, score: None }],
            target: None,
        }
    }

    #[test]
    fn cards_and_syllabus_are_sources_that_go_stale_with_an_edit_and_leave_with_their_owner() {
        let store = Store::in_memory().unwrap();
        store.save_deck(&deck("d1", "DSA", &[("Stack", "LIFO")])).unwrap();
        store.save_deck(&deck("empty", "Nothing", &[])).unwrap();
        let mut snap = Snapshot::default();
        snap.syllabus.insert("COMP 20073".into(), plan("Trees"));
        snap.syllabus.insert("MATH 1".into(), Plan::default());
        store.save(&snap).unwrap();

        let all = store.sources().unwrap();
        assert_eq!(all.iter().map(|s| (s.key.as_str(), s.title.as_str())).collect::<Vec<_>>(), [("card:d1", "Cards · DSA"), ("plan:COMP 20073", "Syllabus · COMP 20073")]);
        assert!(all[0].text.contains("Stack: LIFO") && all[1].text.contains("Week 3 · Quiz: Trees") && all[1].text.contains("Midterm 30%"));

        assert_eq!(store.stale_sources("m").unwrap().len(), 2);
        for s in &all {
            store.replace_chunks(&s.key, s.stamp, "m", &[("x".into(), vec![1.0])]).unwrap();
        }
        assert!(store.stale_sources("m").unwrap().is_empty());
        assert_eq!(store.stale_sources("other").unwrap().len(), 2, "another model's vectors are not reusable");

        store.save_deck(&deck("d1", "DSA", &[("Stack", "LIFO"), ("Queue", "FIFO")])).unwrap();
        assert_eq!(store.stale_sources("m").unwrap().iter().map(|s| s.key.as_str()).collect::<Vec<_>>(), ["card:d1"], "a new card makes the deck stale");
        snap.syllabus.insert("COMP 20073".into(), plan("Graphs"));
        store.save(&snap).unwrap();
        assert_eq!(store.stale_sources("m").unwrap().len(), 2, "a changed topic makes the plan stale");

        snap.syllabus.clear();
        store.save(&snap).unwrap();
        store.prune_chunks().unwrap();
        assert_eq!(store.chunks("m").unwrap().iter().map(|c| c.0.as_str()).collect::<Vec<_>>(), ["card:d1"], "a cleared plan drops its chunks");
        store.delete_deck("d1").unwrap();
        assert!(store.chunks("m").unwrap().is_empty(), "deleting a deck drops its chunks");

        store.save_deck(&deck("d1", "DSA", &[("Stack", "LIFO")])).unwrap();
        store.replace_chunks("card:d1", 1, "m", &[("x".into(), vec![1.0])]).unwrap();
        store.wipe().unwrap();
        assert!(store.chunks("m").unwrap().is_empty() && store.sources().unwrap().is_empty());
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
    #[test]
    fn c15a_21st_photo_refused() {
        let store = Store::in_memory().unwrap();
        for n in 0..20 {
            store.add_photo("note:a", &NewPhoto { w: 10, h: 10, bytes: &[n] }, None, None, 100 + i64::from(n)).unwrap();
        }
        assert!(matches!(store.add_photo("note:a", &NewPhoto { w: 10, h: 10, bytes: &[1] }, None, None, 200), Err(StoreError::TooManyPhotos)));
        assert_eq!(store.photos("note:a").unwrap().len(), 20);
        store.add_photo("note:b", &NewPhoto { w: 10, h: 10, bytes: &[1] }, None, None, 200).unwrap();
        store.set_note("note:c", "x", None, 150).unwrap();
        store.add_photo("note:c", &NewPhoto { w: 10, h: 10, bytes: &[1] }, None, None, 300).unwrap();
        assert_eq!(store.notes().unwrap()[0].key, "note:c", "adding moves the note up");
    }

    #[test]
    fn c17_note_delete_removes_photos() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "words", None, 100).unwrap();
        store.replace_chunks("note:a", 100, "m", &[("words".into(), vec![1.0])]).unwrap();
        let p = store.add_photo("note:a", &NewPhoto { w: 4, h: 3, bytes: &[1, 2, 3] }, None, None, 110).unwrap();
        store.add_photo("note:b", &NewPhoto { w: 4, h: 3, bytes: &[9] }, None, None, 110).unwrap();
        assert_eq!(store.photo_bytes(p.id).unwrap(), [1, 2, 3]);
        store.forget_sis().unwrap();
        assert_eq!(store.photos("note:a").unwrap().len(), 1, "sign-out keeps photos");
        store.delete_note("note:a").unwrap();
        assert!(store.photos("note:a").unwrap().is_empty() && store.chunks("m").unwrap().is_empty());
        assert_eq!(store.photos("note:b").unwrap().len(), 1, "another note's photos stay");
        store.wipe().unwrap();
        assert!(store.photos("note:b").unwrap().is_empty(), "Erase everything removes them");
    }

    #[test]
    fn c17c_kept_row_drops_its_chunks() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "secret words", None, 100).unwrap();
        store.add_photo("note:a", &NewPhoto { w: 4, h: 3, bytes: &[1] }, None, None, 110).unwrap();
        store.replace_chunks("note:a", 110, "m", &[("secret words".into(), vec![1.0])]).unwrap();
        store.set_note("note:a", " ", None, 200).unwrap();
        assert!(store.chunks("m").unwrap().is_empty(), "LAR can't cite erased words");
        assert!(store.sources().unwrap().is_empty(), "nothing to read");
    }

    #[test]
    fn c17c_blank_keeps_a_note_with_photos() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "words", Some("Name"), 100).unwrap();
        let p = store.add_photo("note:a", &NewPhoto { w: 4, h: 3, bytes: &[1] }, None, None, 110).unwrap();
        store.set_note("note:a", "", None, 200).unwrap();
        let n = &store.notes().unwrap()[0];
        assert_eq!((n.text.as_str(), n.photos, n.title.as_deref()), ("", 1, Some("Name")));
        store.delete_photo(p.id).unwrap();
        store.set_note("note:a", "", None, 300).unwrap();
        assert!(store.notes().unwrap().is_empty(), "no photos left, blank deletes");
    }

    #[test]
    fn c17c_first_photo_creates_the_row() {
        let store = Store::in_memory().unwrap();
        store.add_photo("note:new", &NewPhoto { w: 4, h: 3, bytes: &[1] }, Some("Trip"), None, 100).unwrap();
        let n = &store.notes().unwrap()[0];
        assert_eq!((n.key.as_str(), n.text.as_str(), n.title.as_deref(), n.photos, n.updated), ("note:new", "", Some("Trip"), 1, 100));
        assert!(crate::notes::markdown(&store.notes().unwrap()).is_empty(), "export skips the empty section");
    }

    #[test]
    fn c17d_after_class_needs_text() {
        let store = Store::in_memory().unwrap();
        store.add_photo("class:MATH 1", &NewPhoto { w: 4, h: 3, bytes: &[1] }, None, None, 100).unwrap();
        assert!(crate::notes::class_codes_with_text(&store.notes().unwrap()).is_empty());
        store.set_note("class:MATH 2", "Quiz", None, 100).unwrap();
        assert_eq!(crate::notes::class_codes_with_text(&store.notes().unwrap()), ["MATH 2"]);
    }

    #[test]
    fn photos_zip_and_thumbs_and_last_photo_cleanup() {
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "words", Some("Trip"), 100).unwrap();
        let p = store.add_photo("note:a", &NewPhoto { w: 4, h: 3, bytes: &[1, 2] }, None, Some("MATH 1"), 110).unwrap();
        assert_eq!(store.notes().unwrap()[0].subject.as_deref(), Some("MATH 1"));
        assert_eq!(store.photo_thumb(p.id).unwrap(), [1, 2], "no thumb yet: the photo itself");
        store.set_photo_thumb(p.id, &[7]).unwrap();
        assert_eq!(store.photo_thumb(p.id).unwrap(), [7]);
        let mut z = zip::ZipArchive::new(std::io::Cursor::new(store.export_zip(Some("note:a")).unwrap())).unwrap();
        let names: Vec<_> = (0..z.len()).map(|i| z.name_for_index(i).unwrap().unwrap().to_string()).collect();
        assert!(names.contains(&"notes.md".to_string()) && names.contains(&"photos/Trip 1.jpg".to_string()), "{names:?}");
        let mut md = String::new();
        std::io::Read::read_to_string(&mut z.by_name("notes.md").unwrap(), &mut md).unwrap();
        assert!(md.contains("words"));
        // A stale embed can't write erased words back.
        store.set_note("note:a", "", None, 200).unwrap();
        store.replace_chunks("note:a", 110, "m", &[("words".into(), vec![1.0])]).unwrap();
        assert!(store.chunks("m").unwrap().is_empty());
        store.delete_photo(p.id).unwrap();
        assert!(store.notes().unwrap().is_empty(), "no text, no photos: the row goes");
    }
}
