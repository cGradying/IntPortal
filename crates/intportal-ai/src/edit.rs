//! LAR changes a note the student already has (spec 062 C7–C15). The rules read what kind of change is asked
//! and which note it is; the model writes only what changes (line edits, or new lines). Nothing is written
//! here: the chat shows a before-and-after card, and Apply writes it with an undo step kept.
use crate::{intent::words, llm::Llm, note, prompt::Template, reply};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Append,
    Change,
    Tidy,
    Rename,
    Move,
    Delete,
}

/// A note LAR may be asked about. `name` is what the student sees: the title, or the subject for a class note.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct NoteRef {
    pub key: String,
    pub name: String,
    pub subject: Option<String>,
    pub text: String,
}

/// The most notes the "which note?" buttons offer (C8).
pub const PICK_MAX: usize = 4;
/// Tokens for line edits or new lines: they hold only what changes, so a long note costs no more (C9).
pub const EDIT_TOKENS: u32 = 400;

fn has(w: &[String], list: &[&str]) -> bool {
    w.iter().any(|x| list.contains(&x.as_str()))
}

/// The kind of change a message asks for, or None when it asks for none. `note_open`: a note is on screen, so
/// "fix the spelling" needs no "note" to be about it. "Add a note …" is a new note, never an edit.
pub fn kind(msg: &str, note_open: bool) -> Option<Kind> {
    let w = words(msg);
    let joined = format!(" {} ", w.join(" "));
    let names_note = has(&w, &["note", "notes"]);
    if !(names_note || note_open) || has(&w, &["remind", "reminder", "paalala", "flashcard", "flashcards", "card", "cards", "quiz"]) {
        return None;
    }
    let new_note = [" add a note", " new note", " make a note", " create a note", " write a note", " save a note", " take a note", " jot", " note "].iter().any(|p| joined.starts_with(p) || (*p != " note " && joined.contains(p)));
    if new_note {
        return None;
    }
    // "remove heaps from my note" takes a part out; "remove my note from yesterday" deletes the note.
    let at = |list: &[&str]| w.iter().position(|x| list.contains(&x.as_str()));
    let from_a_note = match (at(&["from"]), at(&["note", "notes"])) {
        (Some(f), Some(n)) => f < n,
        (Some(_), None) => true,
        _ => false,
    };
    let part = has(&w, &["line", "lines", "part", "bullet", "sentence", "word", "words", "date", "time"]) || from_a_note;
    if has(&w, &["rename", "retitle"]) || joined.contains(" change the title") || joined.contains(" call it ") || joined.contains(" palitan ang pangalan") || joined.contains(" title to ") {
        Some(Kind::Rename)
    } else if has(&w, &["move", "file", "ilipat"]) || joined.contains(" put it under") {
        Some(Kind::Move)
    } else if has(&w, &["delete", "erase", "burahin", "trash"]) || (has(&w, &["remove", "alisin", "tanggalin"]) && !part) {
        Some(Kind::Delete)
    } else if has(&w, &["tidy", "clean", "organize", "organise", "format", "linisin", "ayusin", "spelling", "grammar", "typos"]) {
        Some(Kind::Tidy)
    } else if has(&w, &["change", "update", "edit", "fix", "replace", "correct", "palitan", "baguhin", "remove", "alisin", "tanggalin"]) {
        Some(Kind::Change)
    } else if has(&w, &["add", "append", "include", "idagdag", "isama", "ilagay", "put"]) && (has(&w, &["to", "into", "in", "sa"]) || note_open) {
        Some(Kind::Append)
    } else {
        None
    }
}

/// Words of the request that say which note, not what to do with it.
fn topic_words(msg: &str) -> Vec<String> {
    const SKIP: &[&str] = &[
        "the", "a", "an", "my", "this", "that", "it", "to", "in", "into", "of", "on", "about", "for", "from", "and", "with", "under", "as", "is", "be", "me", "please", "can", "you", "could", "pls",
        "note", "notes", "rename", "retitle", "move", "file", "delete", "erase", "remove", "trash", "tidy", "clean", "up", "organize", "format", "fix", "spelling", "grammar", "change", "update", "edit", "replace", "correct", "add", "append", "include", "put", "title", "call", "line", "part",
        "ko", "ang", "sa", "ng", "mo", "na", "yung", "ito", "iyan",
    ];
    words(msg).into_iter().filter(|w| w.chars().count() >= 3 && !SKIP.contains(&w.as_str())).collect()
}

/// Which note a request means (C8): the open one, else the notes whose name, subject or text hold the most of
/// the request's own words, a name match counting three. One clear winner, or up to `PICK_MAX` to pick from.
pub enum Target {
    One(NoteRef),
    Pick(Vec<NoteRef>),
    None,
}

pub fn target(msg: &str, open: Option<&NoteRef>, notes: &[NoteRef], subject: Option<&str>) -> Target {
    if let Some(n) = open {
        return Target::One(n.clone());
    }
    let want = topic_words(msg);
    let mut scored: Vec<(usize, &NoteRef)> = notes
        .iter()
        .map(|n| {
            let (name, text) = (words(&n.name), words(&n.text));
            let mut s: usize = want.iter().map(|w| if name.contains(w) { 3 } else if text.contains(w) { 1 } else { 0 }).sum();
            if subject.is_some() && n.subject.as_deref() == subject {
                s += 3;
            }
            (s, n)
        })
        .filter(|(s, _)| *s > 0)
        .collect();
    scored.sort_by_key(|s| std::cmp::Reverse(s.0));
    match scored.as_slice() {
        [] => Target::None,
        [(_, n)] => Target::One((*n).clone()),
        [(a, n), (b, _), ..] if *a >= 2 * b => Target::One((*n).clone()),
        _ => Target::Pick(scored.iter().take(PICK_MAX).map(|(_, n)| (*n).clone()).collect()),
    }
}

/// The new name in "rename this note to Midterm review", "call it 'Heaps'".
pub fn new_title(msg: &str) -> Option<String> {
    // Double quotes only: an apostrophe ("Prof's notes") is not a quote. Single quotes are trimmed below.
    let quoted = msg.split(['"', '\u{201c}', '\u{201d}']).nth(1).map(str::trim).filter(|q| !q.is_empty());
    let after = |k: &str| msg.to_lowercase().rfind(k).map(|i| msg[i + k.len()..].trim().to_string());
    let t = quoted.map(String::from).or_else(|| after(" to ")).or_else(|| after(" as ")).or_else(|| after(" it "))?;
    let t = t.trim_end_matches(['.', '!', '?']).trim().trim_matches(['"', '\'', '\u{201c}', '\u{201d}', '\u{2018}', '\u{2019}']).trim().to_string();
    (!t.is_empty() && t.chars().count() <= 80).then_some(t)
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LineEdit {
    pub op: String,
    pub line: usize,
    #[serde(default)]
    pub text: String,
}

/// Applies line edits to `text` (lines numbered from 1; insert puts its text after `line`, 0 for the top).
/// An edit pointing past the note is dropped. None when nothing is left to apply or nothing changed (C9).
pub fn apply(text: &str, edits: &[LineEdit]) -> Option<String> {
    let mut lines: Vec<String> = text.lines().map(String::from).collect();
    let n = lines.len();
    let mut ok: Vec<(usize, &LineEdit)> = edits.iter().enumerate().filter(|(_, e)| match e.op.as_str() { "insert" => e.line <= n, "replace" | "remove" => (1..=n).contains(&e.line), _ => false }).collect();
    // From the bottom up, so each edit's line number still means the line the model saw. On one line the
    // inserts go first (after the line as it was), last-listed first, so they read in the model's order.
    ok.sort_by_key(|&(i, e)| (std::cmp::Reverse(e.line), e.op != "insert", std::cmp::Reverse(i)));
    for (_, e) in ok {
        match e.op.as_str() {
            "replace" => {
                let was = &lines[e.line - 1];
                // A bullet stays a bullet: Qwen3.5 2B drops the "- " it was shown.
                let lead: String = was.chars().take_while(|c| c.is_whitespace() || *c == '-' || *c == '*' || *c == '•').collect();
                let new = e.text.trim_end();
                lines[e.line - 1] = if !lead.trim().is_empty() && !new.trim_start().starts_with(['-', '*', '•']) { format!("{lead}{}", new.trim_start()) } else { new.to_string() };
            }
            "remove" => drop(lines.remove(e.line - 1)),
            _ => lines.insert(e.line, e.text.trim_end().to_string()),
        }
    }
    let out = lines.join("\n");
    (out.trim() != text.trim()).then_some(out)
}

/// A line's letters and digits, for "is it already there?".
fn key(line: &str) -> String {
    line.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect()
}

fn numbered(text: &str) -> String {
    text.lines().enumerate().map(|(i, l)| format!("{}: {l}\n", i + 1)).collect()
}

const CHANGE: &str = "You edit a student's note. The note's lines are numbered. Return only the lines to change, as edits:
- {\"op\": \"replace\", \"line\": n, \"text\": \"the new line\"} to rewrite line n,
- {\"op\": \"insert\", \"line\": n, \"text\": \"a new line\"} to add a line after line n (0 for the top),
- {\"op\": \"remove\", \"line\": n} to delete line n.
Change only what the student asks; keep every other line, word and fact. When a fact changes (a day, a room, a number), replace the line that holds it: don't add a second line. Use the chat only for facts the student refers to. Reply as JSON.";

const APPEND: &str = "Add to a student's note what they ask for, as new lines that go at its end. Write only the new lines, in the style of the note's lines (a \"- \" bullet if the note uses them). Take the facts from the chat only when the student refers to it (\"what you said\", \"the formula you gave\"). Never repeat a line the note already has. Add nothing they didn't ask for. Reply as JSON.";

/// The chat's last turns, for "add what you just said" (at most ~1,500 characters).
fn recent(chat: &[(String, String)]) -> String {
    let mut out: Vec<String> = vec![];
    let mut used = 0;
    for (me, lar) in chat.iter().rev().take(2) {
        let p = format!("Student: {me}\nLAR: {lar}\n");
        used += p.chars().count();
        if used > 1500 && !out.is_empty() {
            break;
        }
        out.push(p.chars().take(1500).collect());
    }
    out.reverse();
    out.concat()
}

/// The note's new text for Change, Append or Tidy: one model call. Err carries the student-facing line.
pub fn rewrite(llm: &mut dyn Llm, tpl: Template, kind: Kind, note: &NoteRef, chat: &[(String, String)], msg: &str) -> Result<String, String> {
    if note.text.trim().is_empty() && kind != Kind::Append {
        return Err("That note is empty, so there's nothing to change.".into());
    }
    if note.text.chars().count() > note::MAX_NOTE {
        return Err("This note is too long for me to edit at once. Open it and select the part.".into());
    }
    let unchanged = || "That didn't change anything in the note.".to_string();
    // The chat only for "what you said", "the formula you told me": otherwise a 2B model pastes it in.
    let refers = words(msg).iter().any(|w| ["you", "your", "said", "told", "just", "sinabi", "mo", "chat", "earlier", "above"].contains(&w.as_str()));
    let said = if refers { recent(chat) } else { String::new() };
    let chat_part = if said.is_empty() { String::new() } else { format!("\n\nChat:\n{said}") };
    match kind {
        Kind::Tidy => {
            let out = note::run(llm, tpl, note::Mode::Tidy, &note.text, None, None, &mut |_| ())?;
            (out.trim() != note.text.trim()).then_some(out).ok_or_else(unchanged)
        }
        Kind::Change => {
            let schema = json!({"type": "object", "properties": {"edits": {"type": "array", "maxItems": 20, "items": {"type": "object", "properties": {
                "op": {"enum": ["replace", "insert", "remove"]}, "line": {"type": "integer", "minimum": 0}, "text": {"type": "string", "maxLength": 300}}, "required": ["op", "line"]}}}, "required": ["edits"]});
            let user = format!("Note:\n{}{chat_part}\n\nStudent: {msg}", numbered(&note.text));
            let raw = llm.generate(&tpl.wrap(CHANGE, &user), Some(&schema), EDIT_TOKENS, &mut |_| true)?;
            #[derive(Deserialize)]
            struct E {
                edits: Vec<LineEdit>,
            }
            let e: E = reply::parse(&raw).map_err(|e| e.to_string())?;
            apply(&note.text, &e.edits).ok_or_else(unchanged)
        }
        Kind::Append => {
            let schema: Value = json!({"type": "object", "properties": {"lines": {"type": "array", "minItems": 1, "maxItems": 10, "items": {"type": "string", "maxLength": 300}}}, "required": ["lines"]});
            let user = format!("Note:\n{}{chat_part}\n\nStudent: {msg}", note.text);
            let raw = llm.generate(&tpl.wrap(APPEND, &user), Some(&schema), EDIT_TOKENS, &mut |_| true)?;
            #[derive(Deserialize)]
            struct L {
                lines: Vec<String>,
            }
            let l: L = reply::parse(&raw).map_err(|e| e.to_string())?;
            let have: Vec<String> = note.text.lines().map(key).collect();
            let mut add: Vec<&str> = vec![];
            for line in l.lines.iter().map(|s| s.trim_end()).filter(|s| !s.trim().is_empty()) {
                if !have.contains(&key(line)) && !add.iter().any(|a| key(a) == key(line)) {
                    add.push(line);
                }
            }
            if add.is_empty() {
                return Err(unchanged());
            }
            let old = note.text.trim_end();
            Ok(if old.is_empty() { add.join("\n") } else { format!("{old}\n{}", add.join("\n")) })
        }
        Kind::Rename | Kind::Move | Kind::Delete => Err(unchanged()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    fn n(key: &str, name: &str, subject: Option<&str>, text: &str) -> NoteRef {
        NoteRef { key: key.into(), name: name.into(), subject: subject.map(String::from), text: text.into() }
    }

    #[test]
    fn c7_reads_the_kind_of_change() {
        for (msg, open, want) in [
            ("Change the exam date in my COMP note to Friday", false, Some(Kind::Change)),
            ("add the formula to this note", true, Some(Kind::Append)),
            ("add the formula to my Math note", false, Some(Kind::Append)),
            ("fix the spelling in my Math note", false, Some(Kind::Tidy)),
            ("fix the spelling", true, Some(Kind::Tidy)),
            ("tidy up my heaps notes", false, Some(Kind::Tidy)),
            ("rename this note to Midterm review", true, Some(Kind::Rename)),
            ("move this note to MATH 101", true, Some(Kind::Move)),
            ("delete my note about heaps", false, Some(Kind::Delete)),
            ("remove the second line from my heaps note", false, Some(Kind::Change)),
            ("burahin ang note ko sa heaps", false, Some(Kind::Delete)),
            ("palitan mo yung date sa note ko", false, Some(Kind::Change)),
            // Not edits.
            ("Add a note that Prof. Reyes moved the exam", false, None),
            ("Note: bring calculator", false, None),
            ("make flashcards from my heaps note", false, None),
            ("remind me to fix my note", false, None),
            ("Summarize this note", true, None),
            ("fix my sleep schedule", false, None),
        ] {
            assert_eq!(kind(msg, open), want, "{msg}");
        }
    }

    #[test]
    fn c8_finds_the_note_or_asks_which() {
        let notes = [n("note:1", "Heaps", Some("COMP 20073"), "A max-heap keeps the biggest on top"), n("note:2", "Stacks and queues", Some("COMP 20073"), "LIFO and FIFO"), n("class:MATH 101", "MATH 101", Some("MATH 101"), "Quiz Friday")];
        let open = n("note:9", "Open", None, "x");
        assert!(matches!(target("fix it", Some(&open), &notes, None), Target::One(t) if t.key == "note:9"));
        assert!(matches!(target("delete my note about heaps", None, &notes, None), Target::One(t) if t.key == "note:1"));
        assert!(matches!(target("tidy my Math note", None, &notes, Some("MATH 101")), Target::One(t) if t.key == "class:MATH 101"));
        assert!(matches!(target("fix my COMP note", None, &notes, Some("COMP 20073")), Target::Pick(v) if v.len() == 2));
        assert!(matches!(target("delete my note about photosynthesis", None, &notes, None), Target::None));
    }

    #[test]
    fn c9_line_edits_replace_insert_and_remove_from_the_bottom_up() {
        let t = "Quiz Friday\nBring ID\nRoom 302";
        let e = |op: &str, line, text: &str| LineEdit { op: op.into(), line, text: text.into() };
        assert_eq!(apply(t, &[e("replace", 1, "Quiz Monday"), e("remove", 3, ""), e("insert", 0, "COMP 20073")]).unwrap(), "COMP 20073\nQuiz Monday\nBring ID");
        assert_eq!(apply(t, &[e("replace", 9, "x"), e("replace", 2, "Bring ID and calculator")]).unwrap(), "Quiz Friday\nBring ID and calculator\nRoom 302", "a line past the note is dropped");
        assert_eq!(apply(t, &[e("replace", 9, "x")]), None, "nothing left to apply");
        assert_eq!(apply(t, &[e("replace", 1, "Quiz Friday")]), None, "nothing changed");
        assert_eq!(apply("- Insert is O(log n)", &[e("replace", 1, "Insert is O(log n) worst case")]).unwrap(), "- Insert is O(log n) worst case", "a bullet stays a bullet");
    }

    #[test]
    fn c9_c10_change_and_append_are_one_call_that_returns_only_what_changes() {
        let note = n("note:1", "Quiz", None, "Quiz Friday\nBring ID");
        let mut m = FakeLlm::new(&[r#"{"edits":[{"op":"replace","line":1,"text":"Quiz Monday"}]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &[], "change the quiz to Monday").unwrap(), "Quiz Monday\nBring ID");
        assert!(m.prompts[0].contains("1: Quiz Friday\n2: Bring ID"));
        let chat = [("power rule?".to_string(), "d/dx x^n = n x^(n-1)".to_string())];
        let mut m = FakeLlm::new(&[r#"{"lines":["d/dx x^n = n x^(n-1)"]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &chat, "add the formula to this note").unwrap(), "Quiz Friday\nBring ID\nd/dx x^n = n x^(n-1)");
        assert!(!m.prompts[0].contains("LAR: d/dx x^n"), "no chat unless the request points at it");
        let mut m = FakeLlm::new(&[r#"{"lines":["Bring ID","d/dx x^n = n x^(n-1)"]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &chat, "add the formula you told me").unwrap(), "Quiz Friday\nBring ID\nd/dx x^n = n x^(n-1)", "a line it already has is not added again");
        assert!(m.prompts[0].contains("LAR: d/dx x^n"), "the chat is there for 'the formula you told me'");
        assert_eq!(m.prompts.len(), 1);
    }

    #[test]
    fn c15_a_long_note_or_no_change_is_said_plainly() {
        let long = n("note:1", "L", None, &"x".repeat(note::MAX_NOTE + 1));
        assert!(rewrite(&mut FakeLlm::new(&[]), Template::ChatMl, Kind::Change, &long, &[], "fix it").unwrap_err().contains("too long"));
        let note = n("note:1", "Q", None, "Quiz Friday");
        let mut m = FakeLlm::new(&[r#"{"edits":[{"op":"replace","line":1,"text":"Quiz Friday"}]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &[], "fix it").unwrap_err(), "That didn't change anything in the note.");
    }

    fn le(op: &str, line: usize, text: &str) -> LineEdit {
        LineEdit { op: op.into(), line, text: text.into() }
    }

    #[test]
    fn c7_more_ways_to_ask_for_each_kind() {
        for (msg, open, want) in [
            ("append the formula to my Math note", false, Some(Kind::Append)),
            ("include the room in this note", true, Some(Kind::Append)),
            ("idagdag sa note ko ang formula", false, Some(Kind::Append)),
            ("add a line to my heaps note", false, Some(Kind::Append)),
            ("edit my COMP note", false, Some(Kind::Change)),
            ("update the room in my note", false, Some(Kind::Change)),
            ("baguhin ang date sa note ko", false, Some(Kind::Change)),
            ("alisin ang line 2 sa note ko", false, Some(Kind::Change)),
            ("remove the date from my note", false, Some(Kind::Change)),
            ("organize my heaps note", false, Some(Kind::Tidy)),
            ("linisin ang note ko", false, Some(Kind::Tidy)),
            ("check the grammar in this note", true, Some(Kind::Tidy)),
            ("retitle my heaps note to Trees", false, Some(Kind::Rename)),
            ("change the title of this note to Trees", true, Some(Kind::Rename)),
            ("call it Trees", true, Some(Kind::Rename)),
            ("palitan ang pangalan ng note ko", false, Some(Kind::Rename)),
            ("ilipat mo ang note ko sa MATH 101", false, Some(Kind::Move)),
            ("file my heaps note under COMP 20073", false, Some(Kind::Move)),
            ("put it under MATH 101", true, Some(Kind::Move)),
            ("erase my heaps note", false, Some(Kind::Delete)),
            ("trash this note", true, Some(Kind::Delete)),
            ("remove my heaps note", false, Some(Kind::Delete)),
            ("tanggalin ang note ko sa heaps", false, Some(Kind::Delete)),
            ("DELETE MY NOTE ABOUT HEAPS!", false, Some(Kind::Delete)),
        ] {
            assert_eq!(kind(msg, open), want, "{msg}");
        }
    }

    #[test]
    fn c7_a_new_note_a_reminder_cards_or_a_quiz_is_never_an_edit() {
        for (msg, open) in [
            ("add a note about heaps", false),
            ("create a note for my math class", false),
            ("write a note that the exam moved", true),
            ("take a note: delete the old file", true),
            ("jot this down in my notes", false),
            ("Add the formula to a new note", false),
            ("remind me to delete my note", false),
            ("paalala: palitan ang note ko", false),
            ("make flashcards from this note", true),
            ("add a card to my note", true),
            ("make a quiz from my notes", false),
            ("when is the next quiz in my notes", false),
            ("delete this note and make cards", true),
        ] {
            assert_eq!(kind(msg, open), None, "{msg}");
        }
    }

    #[test]
    fn c7_it_must_be_about_a_note_and_name_a_change() {
        assert_eq!(kind("delete it", false), None, "no note named, none open");
        assert_eq!(kind("fix the spelling", false), None);
        assert_eq!(kind("what does my note say", false), None, "a question about a note is not an edit");
        assert_eq!(kind("show me my notes", false), None);
        assert_eq!(kind("hello", true), None);
        assert_eq!(kind("", true), None);
    }

    #[test]
    fn c7_removing_a_part_changes_the_note_but_removing_the_note_deletes_it() {
        assert_eq!(kind("remove the last bullet from my note", false), Some(Kind::Change));
        assert_eq!(kind("remove the first sentence of this note", true), Some(Kind::Change));
    }

    #[test]
    fn c7_remove_my_note_from_a_day_deletes_the_note() {
        assert_eq!(kind("remove my note from yesterday", false), Some(Kind::Delete));
    }

    fn pool() -> Vec<NoteRef> {
        vec![
            n("note:1", "Heaps", Some("COMP 20073"), "A max-heap keeps the biggest on top"),
            n("note:2", "Trees", Some("COMP 20073"), "Heaps are trees"),
            n("note:3", "Stacks", Some("COMP 20073"), "LIFO"),
            n("class:MATH 101", "MATH 101", Some("MATH 101"), "Quiz Friday"),
        ]
    }

    #[test]
    fn c8_a_name_match_counts_three_and_a_text_match_one() {
        // "heaps": name of note 1 (3) against the text of note 2 (1): 3 >= 2 * 1, so note 1 wins clearly.
        assert!(matches!(target("delete my heaps note", None, &pool(), None), Target::One(t) if t.key == "note:1"));
        // Only a text match is still a match.
        assert!(matches!(target("delete my note about biggest", None, &pool(), None), Target::One(t) if t.key == "note:1"));
    }

    #[test]
    fn c8_the_subject_in_the_request_adds_three() {
        // "stacks" is a name match for note 3 (3). Subject adds 3 to every COMP note: 3 -> 6, others 0 -> 3.
        let notes = [n("note:a", "Stacks", Some("COMP 20073"), ""), n("note:b", "Queues", Some("MATH 101"), "stacks")];
        // a: 3 + 3 = 6, b: 1. A clear winner.
        assert!(matches!(target("tidy my stacks note", None, &notes, Some("COMP 20073")), Target::One(t) if t.key == "note:a"));
        // With a subject only (no topic words) every note in it ties: the student picks.
        assert!(matches!(target("tidy my COMP note", None, &pool(), Some("COMP 20073")), Target::Pick(v) if v.len() == 3));
    }

    #[test]
    fn c8_a_clear_winner_needs_twice_the_next_score() {
        let top = |text: &str| n("note:1", "x", None, text);
        let other = |text: &str| n("note:2", "y", None, text);
        // 2 text hits against 1: exactly twice, so one note.
        let notes = [top("alpha beta"), other("alpha")];
        assert!(matches!(target("fix alpha beta", None, &notes, None), Target::One(t) if t.key == "note:1"));
        // 3 (a name hit) against 2: less than twice, so the student picks, best first.
        let notes = [other("alpha beta"), n("note:1", "Alpha", None, "")];
        match target("fix alpha beta", None, &notes, None) {
            Target::Pick(v) => assert_eq!(v.iter().map(|n| n.key.as_str()).collect::<Vec<_>>(), ["note:1", "note:2"]),
            _ => panic!("3 against 2 is not a clear winner"),
        }
        // A tie is a pick, in the order the notes came.
        let notes = [n("note:1", "Heaps", None, ""), n("note:2", "Heaps", None, "")];
        assert!(matches!(target("delete my heaps note", None, &notes, None), Target::Pick(v) if v[0].key == "note:1" && v.len() == 2));
    }

    #[test]
    fn c8_never_more_than_four_buttons() {
        let notes: Vec<NoteRef> = (0..7).map(|i| n(&format!("note:{i}"), "Heaps", None, "")).collect();
        assert!(matches!(target("delete my heaps note", None, &notes, None), Target::Pick(v) if v.len() == PICK_MAX));
    }

    #[test]
    fn c8_the_open_note_wins_over_a_better_match_and_with_no_notes_at_all() {
        let open = n("note:9", "Open", None, "x");
        assert!(matches!(target("delete my heaps note", Some(&open), &pool(), None), Target::One(t) if t.key == "note:9"));
        assert!(matches!(target("delete my heaps note", Some(&open), &[], None), Target::One(_)));
    }

    #[test]
    fn c8_no_match_means_none_not_a_guess() {
        assert!(matches!(target("delete my note", None, &pool(), None), Target::None), "no topic words, no subject");
        assert!(matches!(target("delete my heaps note", None, &[], None), Target::None));
        // Short words and request words don't count as the topic.
        assert!(matches!(target("fix it up to my note", None, &[n("note:1", "Up to it", None, "it up")], None), Target::None));
        // A subject the note doesn't have adds nothing.
        assert!(matches!(target("tidy my note", None, &pool(), Some("PHYS 1")), Target::None));
    }

    #[test]
    fn c12_the_new_title_has_its_edge_cases() {
        assert_eq!(new_title("retitle this note as Heaps and stacks.").as_deref(), Some("Heaps and stacks"));
        assert_eq!(new_title("rename it to “Midterm”").as_deref(), Some("Midterm"));
        assert_eq!(new_title("change the title to Week 3 recap!").as_deref(), Some("Week 3 recap"));
        assert_eq!(new_title("call it Heaps").as_deref(), Some("Heaps"));
        assert_eq!(new_title(&format!("rename this note to {}", "x".repeat(81))), None, "80 characters at most");
        assert_eq!(new_title(&format!("rename this note to {}", "x".repeat(80))).map(|t| t.len()), Some(80));
        assert_eq!(new_title(""), None);
    }

    #[test]
    fn c12_an_empty_quote_names_nothing() {
        assert_eq!(new_title("rename this note to \"\""), None);
    }

    #[test]
    fn c12_an_apostrophe_in_the_new_title_is_part_of_it() {
        assert_eq!(new_title("rename my note to Prof's notes").as_deref(), Some("Prof's notes"));
    }

    #[test]
    fn c9_remove_edits_go_bottom_up_so_each_number_is_the_line_the_model_saw() {
        assert_eq!(apply("a\nb\nc\nd", &[le("remove", 1, ""), le("remove", 2, "")]).unwrap(), "c\nd");
        assert_eq!(apply("a\nb\nc\nd", &[le("remove", 2, ""), le("remove", 1, "")]).unwrap(), "c\nd", "the order the model listed them in does not matter");
        assert_eq!(apply("a\nb\nc", &[le("remove", 1, ""), le("replace", 3, "C")]).unwrap(), "b\nC");
        assert_eq!(apply("a\nb\nc", &[le("replace", 3, "C"), le("insert", 1, "x")]).unwrap(), "a\nx\nb\nC");
    }

    #[test]
    fn c9_insert_at_the_top_after_the_last_line_and_past_it() {
        assert_eq!(apply("a\nb", &[le("insert", 0, "top")]).unwrap(), "top\na\nb");
        assert_eq!(apply("a\nb", &[le("insert", 2, "end")]).unwrap(), "a\nb\nend", "after the last line is in range");
        assert_eq!(apply("a\nb", &[le("insert", 3, "lost")]), None, "past the end is dropped");
        assert_eq!(apply("a\nb", &[le("insert", 3, "lost"), le("insert", 1, "mid")]).unwrap(), "a\nmid\nb");
    }

    #[test]
    fn c9_lines_out_of_range_or_unknown_ops_are_dropped() {
        assert_eq!(apply("a\nb", &[le("replace", 0, "x")]), None, "line 0 is not a line to replace");
        assert_eq!(apply("a\nb", &[le("remove", 0, "")]), None);
        assert_eq!(apply("a\nb", &[le("remove", 3, "")]), None);
        assert_eq!(apply("a\nb", &[le("rewrite", 1, "x")]), None, "an op it doesn't know");
        assert_eq!(apply("a\nb", &[]), None);
        assert_eq!(apply("a\nb", &[le("bogus", 1, "x"), le("replace", 2, "B")]).unwrap(), "a\nB");
    }

    #[test]
    fn c9_a_replaced_bullet_keeps_its_lead() {
        assert_eq!(apply("- a\n* b\n  - c\n• d", &[le("replace", 1, "A"), le("replace", 2, "B"), le("replace", 3, "C"), le("replace", 4, "D")]).unwrap(), "- A\n* B\n  - C\n• D");
        assert_eq!(apply("- a", &[le("replace", 1, "- b")]).unwrap(), "- b", "it already has its own bullet");
        assert_eq!(apply("- a", &[le("replace", 1, "* b")]).unwrap(), "* b", "the model's own bullet wins");
        assert_eq!(apply("plain", &[le("replace", 1, "  - b  ")]).unwrap(), "  - b", "a plain line takes the text as it is, trailing space trimmed");
        assert_eq!(apply("- a", &[le("replace", 1, "a")]), None, "same words under the same bullet is no change");
    }

    #[test]
    fn c9_an_edit_that_only_changes_trailing_blank_space_changes_nothing() {
        assert_eq!(apply("a\nb\n", &[le("replace", 2, "b")]), None);
    }

    #[test]
    fn c9_two_inserts_after_the_same_line_keep_the_order_given() {
        assert_eq!(apply("a\nb", &[le("insert", 1, "x"), le("insert", 1, "y")]).unwrap(), "a\nx\ny\nb");
    }

    #[test]
    fn c9_a_remove_and_an_insert_at_the_same_line_number_use_the_original_numbers() {
        assert_eq!(apply("a\nb\nc", &[le("remove", 1, ""), le("insert", 1, "x")]).unwrap(), "x\nb\nc");
    }

    #[test]
    fn c10_append_drops_repeats_blank_lines_and_lines_the_note_has() {
        let note = n("note:1", "Q", None, "- Quiz Friday\n- Bring ID\n");
        let mut m = FakeLlm::new(&[r#"{"lines":["- bring id.","","- Room 302","- ROOM 302!","   ","Calculator"]}"#]);
        assert_eq!(
            rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &[], "add the room and calculator to my note").unwrap(),
            "- Quiz Friday\n- Bring ID\n- Room 302\nCalculator",
            "the note's own trailing newline is not doubled"
        );
        let mut m = FakeLlm::new(&[r#"{"lines":["Quiz Friday","bring ID"]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &[], "add the quiz to my note").unwrap_err(), "That didn't change anything in the note.");
        let mut m = FakeLlm::new(&[r#"{"lines":["", "  "]}"#]);
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &[], "add it to my note").is_err());
    }

    #[test]
    fn c10_an_empty_note_can_be_appended_to_but_not_changed() {
        let empty = n("note:1", "E", None, "  \n");
        let mut m = FakeLlm::new(&[r#"{"lines":["First line","Second"]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Append, &empty, &[], "add a first line to this note").unwrap(), "First line\nSecond");
        let mut m = FakeLlm::new(&[]);
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Change, &empty, &[], "fix this note").unwrap_err().contains("empty"));
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Tidy, &empty, &[], "tidy this note").unwrap_err().contains("empty"));
        assert!(m.prompts.is_empty(), "no model call for nothing");
    }

    #[test]
    fn c10_the_chat_goes_in_only_when_the_request_points_at_it() {
        let chat = [("old".to_string(), "older answer".to_string()), ("power rule?".to_string(), "LAR said d/dx x^n".to_string())];
        let note = n("note:1", "Q", None, "Quiz Friday");
        for (msg, pointed) in [("add a line about Monday to this note", false), ("add what you said to this note", true), ("idagdag ang sinabi mo sa note", true), ("add the formula from above", true), ("add the chat to this note", true)] {
            let mut m = FakeLlm::new(&[r#"{"lines":["new line"]}"#]);
            rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &chat, msg).unwrap();
            assert_eq!(m.prompts[0].contains("Chat:") && m.prompts[0].contains("LAR said d/dx x^n"), pointed, "{msg}");
            assert!(!m.prompts[0].contains("older answer") || !pointed || chat.len() <= 2, "only the last two turns");
        }
        let mut m = FakeLlm::new(&[r#"{"edits":[{"op":"replace","line":1,"text":"Quiz Monday"}]}"#]);
        rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &chat, "change it to what you said").unwrap();
        assert!(m.prompts[0].contains("LAR said d/dx x^n"), "Change gets the chat too when pointed at");
        let mut m = FakeLlm::new(&[r#"{"edits":[{"op":"replace","line":1,"text":"Quiz Monday"}]}"#]);
        rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &chat, "change friday to monday").unwrap();
        assert!(!m.prompts[0].contains("Chat:"));
    }

    #[test]
    fn c10_a_pointed_at_chat_with_no_turns_adds_no_empty_chat_section() {
        let note = n("note:1", "Q", None, "Quiz Friday");
        let mut m = FakeLlm::new(&[r#"{"lines":["new"]}"#]);
        rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &[], "add what you said to this note").unwrap();
        assert!(!m.prompts[0].contains("Chat:"));
    }

    #[test]
    fn c9_every_edit_out_of_range_or_a_broken_reply_is_said_plainly() {
        let note = n("note:1", "Q", None, "Quiz Friday");
        let mut m = FakeLlm::new(&[r#"{"edits":[{"op":"replace","line":9,"text":"x"},{"op":"remove","line":5}]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &[], "fix it").unwrap_err(), "That didn't change anything in the note.");
        let mut m = FakeLlm::new(&[r#"{"edits":[]}"#]);
        assert_eq!(rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &[], "fix it").unwrap_err(), "That didn't change anything in the note.");
        let mut m = FakeLlm::new(&["I changed it!"]);
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Change, &note, &[], "fix it").is_err());
        let mut m = FakeLlm::new(&[]);
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Append, &note, &[], "add x to my note").is_err(), "a model that fails is an error, not a panic");
    }

    #[test]
    fn c15_a_note_of_exactly_the_limit_is_still_edited_one_over_is_not() {
        let at = n("note:1", "L", None, &"x".repeat(note::MAX_NOTE));
        let mut m = FakeLlm::new(&[r#"{"lines":["more"]}"#]);
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Append, &at, &[], "add more to this note").is_ok());
        let over = n("note:1", "L", None, &"x".repeat(note::MAX_NOTE + 1));
        for k in [Kind::Append, Kind::Tidy, Kind::Change] {
            assert!(rewrite(&mut FakeLlm::new(&[]), Template::ChatMl, k, &over, &[], "edit this note").unwrap_err().contains("too long"), "{k:?}");
        }
    }

    #[test]
    fn c15_the_limit_counts_characters_not_bytes() {
        let ok = n("note:1", "L", None, &"é".repeat(note::MAX_NOTE));
        let mut m = FakeLlm::new(&[r#"{"lines":["more"]}"#]);
        assert!(rewrite(&mut m, Template::ChatMl, Kind::Append, &ok, &[], "add more to this note").is_ok());
    }

    #[test]
    fn c12_the_new_title_is_read_from_the_request() {
        assert_eq!(new_title("rename this note to Midterm review").as_deref(), Some("Midterm review"));
        assert_eq!(new_title("call it \"Heaps and stacks\"").as_deref(), Some("Heaps and stacks"));
        assert_eq!(new_title("rename it"), None);
    }
}
