//! Classes the student adds themselves (spec 061 C1 to C4). On the week an own
//! class is plain sessions with `own` set, so every screen reads it like a
//! synced one; here it is grouped back into one class with its meetings.

use crate::model::{ClassSession, Weekday};
use crate::store::Snapshot;
use serde::{Deserialize, Serialize};

/// Some days at one time.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Meeting {
    pub days: Vec<Weekday>,
    /// Minutes from midnight.
    pub start: u16,
    pub end: u16,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct OwnClass {
    /// Empty means "make one from the name".
    #[serde(default)]
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub room: String,
    #[serde(default)]
    pub teacher: String,
    pub meetings: Vec<Meeting>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum Problem {
    #[error("Give the class a name.")]
    NoName,
    #[error("Pick at least one day.")]
    NoDay,
    #[error("It has to end after it starts.")]
    EndsFirst,
    #[error("That class is already on your week.")]
    Taken,
}

/// The first letter of each word and every digit, upper case: "Calculus 1" is
/// "C1". A code already used gets "-2", "-3".
pub fn make_code(name: &str, taken: &[&str]) -> String {
    let mut base = String::new();
    for word in name.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()) {
        if word.chars().all(|c| c.is_ascii_digit()) {
            base.push_str(word);
        } else if let Some(first) = word.chars().next() {
            base.extend(first.to_uppercase());
        }
    }
    if base.is_empty() {
        base = "CLASS".into();
    }
    let mut code = base.clone();
    let mut n = 2;
    while taken.contains(&code.as_str()) {
        code = format!("{base}-{n}");
        n += 1;
    }
    code
}

/// One session per day per meeting.
pub fn sessions_of(c: &OwnClass) -> Vec<ClassSession> {
    c.meetings
        .iter()
        .flat_map(|m| m.days.iter().map(move |&day| (day, m.start, m.end)))
        .map(|(day, start, end)| ClassSession {
            subject_code: c.code.clone(),
            description: c.name.clone(),
            faculty: c.teacher.clone(),
            day,
            start,
            end,
            occurrence: 0,
            own: true,
            room: c.room.clone(),
        })
        .collect()
}

/// The own sessions grouped back into classes, in the order they were added;
/// days at the same time are one meeting.
pub fn classes_of(sessions: &[ClassSession]) -> Vec<OwnClass> {
    let mut out: Vec<OwnClass> = vec![];
    for s in sessions.iter().filter(|s| s.own) {
        let i = match out.iter().position(|c| c.code == s.subject_code) {
            Some(i) => i,
            None => {
                out.push(OwnClass { code: s.subject_code.clone(), name: s.description.clone(), room: s.room.clone(), teacher: s.faculty.clone(), meetings: vec![] });
                out.len() - 1
            }
        };
        let c = &mut out[i];
        match c.meetings.iter_mut().find(|m| m.start == s.start && m.end == s.end) {
            Some(m) if !m.days.contains(&s.day) => m.days.push(s.day),
            Some(_) => {}
            None => c.meetings.push(Meeting { days: vec![s.day], start: s.start, end: s.end }),
        }
    }
    for m in out.iter_mut().flat_map(|c| c.meetings.iter_mut()) {
        m.days.sort();
    }
    out
}

fn check(c: &OwnClass) -> Result<(), Problem> {
    if c.name.trim().is_empty() {
        return Err(Problem::NoName);
    }
    if c.meetings.is_empty() || c.meetings.iter().any(|m| m.days.is_empty()) {
        return Err(Problem::NoDay);
    }
    if c.meetings.iter().any(|m| m.end <= m.start || m.end > 24 * 60) {
        return Err(Problem::EndsFirst);
    }
    Ok(())
}

/// Adds a class, or replaces the own class whose code was `was` (C3, C4).
/// Returns the code it was saved under.
pub fn save(snap: &mut Snapshot, was: Option<&str>, mut c: OwnClass) -> Result<String, Problem> {
    check(&c)?;
    let trim = |s: &str| s.split_whitespace().collect::<Vec<_>>().join(" ");
    c.name = trim(&c.name);
    c.room = trim(&c.room);
    c.teacher = trim(&c.teacher);
    c.code = trim(&c.code).to_uppercase();
    let rest: Vec<ClassSession> = snap.sessions.iter().filter(|s| !(s.own && Some(s.subject_code.as_str()) == was)).cloned().collect();
    if c.code.is_empty() {
        let taken: Vec<&str> = rest.iter().map(|s| s.subject_code.as_str()).collect();
        c.code = make_code(&c.name, &taken);
    }
    let new = sessions_of(&c);
    let mut ids: Vec<String> = rest.iter().map(ClassSession::id).collect();
    for s in &new {
        let id = s.id();
        if ids.contains(&id) {
            return Err(Problem::Taken);
        }
        ids.push(id);
    }
    if let Some(old) = was.filter(|w| *w != c.code) {
        if let Some(colour) = snap.colors.remove(old) {
            snap.colors.insert(c.code.clone(), colour);
        }
    }
    snap.sessions = rest;
    snap.sessions.extend(new);
    Ok(c.code)
}

pub fn remove(snap: &mut Snapshot, code: &str) {
    snap.sessions.retain(|s| !(s.own && s.subject_code == code));
}

#[cfg(test)]
mod tests {
    use super::*;
    use Weekday::*;

    fn calc() -> OwnClass {
        OwnClass { name: "Calculus 1".into(), meetings: vec![Meeting { days: vec![Monday, Wednesday], start: 450, end: 540 }], ..Default::default() }
    }

    fn synced(code: &str, day: Weekday, start: u16, end: u16) -> ClassSession {
        ClassSession { own: false, room: String::new(), subject_code: code.into(), description: "x".into(), faculty: String::new(), day, start, end, occurrence: 0 }
    }

    #[test]
    fn codes_come_from_the_name_and_never_repeat() {
        assert_eq!(make_code("Calculus 1", &[]), "C1");
        assert_eq!(make_code("Purposive Communication", &[]), "PC");
        assert_eq!(make_code("Calculus 1", &["C1"]), "C1-2");
        assert_eq!(make_code("Calculus 1", &["C1", "C1-2"]), "C1-3");
        assert_eq!(make_code("!!", &[]), "CLASS");
    }

    #[test]
    fn a_class_is_one_own_session_per_day_and_groups_back() {
        let mut snap = Snapshot::default();
        assert_eq!(save(&mut snap, None, calc()), Ok("C1".into()));
        let days: Vec<_> = snap.sessions.iter().map(|s| (s.day, s.own, s.subject_code.as_str())).collect();
        assert_eq!(days, [(Monday, true, "C1"), (Wednesday, true, "C1")]);
        let back = classes_of(&snap.sessions);
        assert_eq!(back.len(), 1);
        assert_eq!(back[0].meetings, [Meeting { days: vec![Monday, Wednesday], start: 450, end: 540 }]);
    }

    #[test]
    fn checks_say_what_is_missing() {
        let mut snap = Snapshot::default();
        assert_eq!(save(&mut snap, None, OwnClass { name: " ".into(), ..calc() }), Err(Problem::NoName));
        assert_eq!(save(&mut snap, None, OwnClass { meetings: vec![], ..calc() }), Err(Problem::NoDay));
        let backwards = Meeting { days: vec![Friday], start: 600, end: 600 };
        assert_eq!(save(&mut snap, None, OwnClass { meetings: vec![backwards], ..calc() }), Err(Problem::EndsFirst));
        assert!(snap.sessions.is_empty(), "nothing saved on a refusal");
    }

    #[test]
    fn the_same_class_twice_is_refused_but_an_edit_replaces_it() {
        let mut snap = Snapshot::default();
        save(&mut snap, None, OwnClass { code: "c1".into(), ..calc() }).unwrap();
        assert_eq!(save(&mut snap, None, OwnClass { code: "C1".into(), ..calc() }), Err(Problem::Taken));
        let moved = OwnClass { code: "MATH 1".into(), meetings: vec![Meeting { days: vec![Friday], start: 600, end: 690 }], ..calc() };
        snap.colors.insert("C1".into(), "#f00".into());
        assert_eq!(save(&mut snap, Some("C1"), moved), Ok("MATH 1".into()));
        assert_eq!(snap.sessions.len(), 1);
        assert_eq!((snap.sessions[0].day, snap.colors.get("MATH 1").map(String::as_str)), (Friday, Some("#f00")));
        remove(&mut snap, "MATH 1");
        assert!(snap.sessions.is_empty());
    }

    #[test]
    fn synced_classes_are_never_edited_or_removed_here() {
        let mut snap = Snapshot { sessions: vec![synced("C1", Tuesday, 600, 690)], ..Default::default() };
        assert_eq!(save(&mut snap, Some("C1"), calc()), Ok("C1-2".into()), "a synced C1 keeps its code");
        remove(&mut snap, "C1");
        assert_eq!(snap.sessions.iter().filter(|s| !s.own).count(), 1);
    }
}
