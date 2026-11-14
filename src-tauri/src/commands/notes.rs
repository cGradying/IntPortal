use crate::*;

#[derive(Serialize)]
pub struct NoteItem {
    #[serde(flatten)]
    note: Note,
    preview: String,
}

/// Every note, pinned ones first, then the latest edit first, with a one-line preview.
#[tauri::command(async)]
pub fn notes(state: tauri::State<'_, AppState>) -> Res<Vec<NoteItem>> {
    let mut list = state.store.lock().unwrap().notes().map_err(err)?;
    notes::pinned_first(&mut list);
    Ok(list.into_iter().map(|note| NoteItem { preview: notes::preview(&note.text, 80), note }).collect())
}

/// Notes as Markdown: one note by `key`, or every note when it's empty.
#[tauri::command(async)]
pub fn notes_markdown(state: tauri::State<'_, AppState>, key: Option<String>) -> Res<String> {
    let mut list = state.store.lock().unwrap().notes().map_err(err)?;
    if let Some(k) = key {
        list.retain(|n| n.key == k);
    }
    Ok(notes::markdown(&list))
}

/// Saves as the student types; blank text deletes the note.
#[tauri::command(async)]
pub fn set_note(state: tauri::State<'_, AppState>, key: String, text: String, title: Option<String>) -> Res<()> {
    if !notes::is_known_key(&key) {
        return Err("Unknown note".into());
    }
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    state.store.lock().unwrap().set_note(&key, &text, title.as_deref(), now).map_err(err)
}

/// Deletes a note with its photos and AI chunks, in one transaction (046 C17).
#[tauri::command]
pub async fn delete_note(app: tauri::AppHandle, key: String) -> Res<()> {
    blocking(app, move |state| state.store.lock().unwrap().delete_note(&key).map_err(err)).await
}

/// Where the camera plugin may leave a photo for `add_photo` to take in.
#[tauri::command]
pub async fn photo_dir(app: tauri::AppHandle) -> Res<String> {
    blocking(app, |state| {
        let dir = state.dir.join(PHOTO_TMP);
        std::fs::create_dir_all(&dir).map_err(err)?;
        Ok(dir.to_string_lossy().into_owned())
    })
    .await
}

/// Takes the photo the plugin saved at `path` into the note's rows and deletes the file, even when it is refused.
/// A note with no row gets one, filed under `subject` (046 C17c).
#[tauri::command]
pub async fn add_photo(app: tauri::AppHandle, key: String, path: String, width: u32, height: u32, title: Option<String>, subject: Option<String>) -> Res<Photo> {
    blocking(app, move |state| {
        let file = std::fs::canonicalize(&path).map_err(err)?;
        if !file.starts_with(std::fs::canonicalize(state.dir.join(PHOTO_TMP)).map_err(err)?) {
            return Err("That photo isn't where it should be.".to_string());
        }
        let bytes = std::fs::read(&file);
        let _ = std::fs::remove_file(&file);
        if !notes::is_known_key(&key) {
            return Err("Unknown note".into());
        }
        let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
        let photo = state.store.lock().unwrap().add_photo(&key, &NewPhoto { w: width, h: height, bytes: &bytes.map_err(err)? }, title.as_deref(), subject.as_deref(), now).map_err(err);
        photo
    })
    .await
}

/// A note's photos, without their bytes.
#[tauri::command]
pub async fn note_photos(app: tauri::AppHandle, key: String) -> Res<Vec<Photo>> {
    blocking(app, move |state| state.store.lock().unwrap().photos(&key).map_err(err)).await
}

/// One photo's JPEG, as raw bytes.
#[tauri::command]
pub async fn photo_bytes(app: tauri::AppHandle, id: i64) -> Res<tauri::ipc::Response> {
    blocking(app, move |state| state.store.lock().unwrap().photo_bytes(id).map(tauri::ipc::Response::new).map_err(err)).await
}

/// The strip's small copy of a photo, as raw bytes.
#[tauri::command]
pub async fn photo_thumb(app: tauri::AppHandle, id: i64) -> Res<tauri::ipc::Response> {
    blocking(app, move |state| state.store.lock().unwrap().photo_thumb(id).map(tauri::ipc::Response::new).map_err(err)).await
}

#[tauri::command]
pub async fn set_photo_thumb(app: tauri::AppHandle, id: i64, thumb: Vec<u8>) -> Res<()> {
    blocking(app, move |state| state.store.lock().unwrap().set_photo_thumb(id, &thumb).map_err(err)).await
}

#[tauri::command]
pub async fn delete_photo(app: tauri::AppHandle, id: i64) -> Res<()> {
    blocking(app, move |state| state.store.lock().unwrap().delete_photo(id).map_err(err)).await
}

/// A note, or every note, as a `.zip` of its Markdown and photos (046 C17).
#[tauri::command]
pub async fn notes_zip(app: tauri::AppHandle, key: Option<String>) -> Res<tauri::ipc::Response> {
    blocking(app, move |state| state.store.lock().unwrap().export_zip(key.as_deref()).map(tauri::ipc::Response::new).map_err(err)).await
}

/// Pinning isn't an edit: the note keeps its place and its AI chunks.
#[tauri::command(async)]
pub fn set_note_pin(state: tauri::State<'_, AppState>, key: String, pinned: bool) -> Res<()> {
    state.store.lock().unwrap().set_note_pin(&key, pinned).map_err(err)
}

/// Files a freeform note under a subject, or none. Not an edit, like a pin.
#[tauri::command(async)]
pub fn set_note_subject(state: tauri::State<'_, AppState>, key: String, subject: Option<String>) -> Res<()> {
    state.store.lock().unwrap().set_note_subject(&key, subject.as_deref()).map_err(err)
}

/// The date a new entry in a class note belongs to (spec 046 C14).
#[tauri::command(async)]
pub fn entry_date(state: tauri::State<'_, AppState>, code: String, today: Date) -> Res<Date> {
    let snap = snapshot_of(&state)?;
    Ok(today::entry_date(&snap.sessions, &snap.marks, &code, today))
}
