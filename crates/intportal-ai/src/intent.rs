//! What the student is asking for, decided by rules, not by the model.
//! Gemma 3 1B answered every "remind me" and "add a note" in words and
//! proposed no action (PR #87's eval), so the rules pick the action and the
//! schema then forces it. The model only writes the reply and fills the text.
use intportal_core::{model::Weekday, today::Date};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Intent {
    Ask,
    Note,
    Remind,
    Cards,
    /// Questions the app can answer exactly from its own data, so the model never guesses.
    Due,
    Classes,
    Grades,
}

fn words(msg: &str) -> Vec<String> {
    msg.to_lowercase().split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).map(String::from).collect()
}

/// Reminders beat cards beat notes: "remind me to make a note" is a reminder.
pub fn detect(msg: &str) -> Intent {
    let w = words(msg);
    let has = |list: &[&str]| w.iter().any(|x| list.contains(&x.as_str()));
    if has(&["remind", "reminder", "paalala", "ipaalala", "alarm"]) {
        Intent::Remind
    } else if has(&["flashcard", "flashcards", "card", "cards"]) {
        Intent::Cards
    } else if has(&["note", "isulat"]) {
        Intent::Note
    } else if has(&["due", "deadline", "deadlines", "pasahan", "exam", "exams", "quiz", "quizzes", "pagsusulit", "assignment", "assignments", "homework", "takdang", "ipasa"]) {
        Intent::Due
    } else if has(&["class", "classes", "klase", "schedule", "iskedyul", "sched"]) {
        Intent::Classes
    } else if has(&["gwa", "grade", "grades", "grado", "standing", "pasado", "bagsak", "pass", "passing", "average", "gpa"]) {
        Intent::Grades
    } else {
        Intent::Ask
    }
}

/// True when the message reads as Filipino or Taglish, so the canned reply matches.
pub fn is_filipino(msg: &str) -> bool {
    const FIL: [&str; 16] = ["ang", "ano", "ko", "ako", "mo", "ba", "naman", "ngayon", "bukas", "kailan", "klase", "pasahan", "mga", "may", "po", "lang"];
    words(msg).iter().filter(|w| FIL.contains(&w.as_str())).count() >= 1
}

/// The one subject a message is about: its code ("MATH 101" or "math101"),
/// the letters of its code ("math"), or a word of its description
/// ("calculus"). None when it names none or more than one.
/// `subjects` is (code, description).
pub fn subject_in(msg: &str, subjects: &[(String, String)]) -> Option<String> {
    let w = words(msg);
    let squashed = w.concat();
    let letters = |code: &str| code.chars().take_while(|c| c.is_alphabetic()).collect::<String>().to_lowercase();
    let only = |hit: Vec<&String>| (hit.len() == 1).then(|| hit[0].clone());
    let by_code = subjects.iter().map(|(c, _)| c).filter(|c| squashed.contains(&c.to_lowercase().replace(' ', ""))).collect();
    only(by_code)
        .or_else(|| only(subjects.iter().map(|(c, _)| c).filter(|c| letters(c).len() >= 3 && w.contains(&letters(c))).collect()))
        .or_else(|| only(subjects.iter().filter(|(_, d)| words(d).iter().any(|dw| dw.chars().count() >= 5 && w.contains(dw))).map(|(c, _)| c).collect()))
}

/// A day the message names ("bukas", "tomorrow", "sa Lunes"), or None when
/// it names none or an unclear one. The model never computes dates.
pub fn resolve_when(msg: &str, today: Date) -> Option<Date> {
    let w = words(msg);
    for (i, x) in w.iter().enumerate() {
        let day = match x.as_str() {
            "today" | "ngayon" | "mamaya" => return Some(today),
            "tomorrow" | "bukas" => return Some(today.add_days(1)),
            "makalawa" => return Some(today.add_days(2)),
            "monday" | "lunes" => Weekday::Monday,
            "tuesday" | "martes" => Weekday::Tuesday,
            "wednesday" | "miyerkules" => Weekday::Wednesday,
            "thursday" | "huwebes" => Weekday::Thursday,
            "friday" | "biyernes" => Weekday::Friday,
            "saturday" | "sabado" => Weekday::Saturday,
            "sunday" => Weekday::Sunday,
            // "linggo" also means "week": only "sa linggo" is Sunday.
            "linggo" if i > 0 && w[i - 1] == "sa" => Weekday::Sunday,
            _ => continue,
        };
        let ahead = (i64::from(day.number()) - i64::from(today.weekday().number())).rem_euclid(7);
        return Some(today.add_days(if ahead == 0 { 7 } else { ahead }));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const THU: Date = Date { y: 2026, m: 10, d: 15 };

    #[test]
    fn picks_the_action_in_english_and_filipino() {
        for (msg, want) in [
            ("Pwede mo ba akong i-remind bukas about Math?", Intent::Remind),
            ("Mag-remind ka sa akin na bayaran ang tuition sa Lunes.", Intent::Remind),
            ("Paalala lang sa quiz", Intent::Remind),
            ("Pa-add naman ng note: bring calculator", Intent::Note),
            ("Add a note that Prof. Reyes moved the exam", Intent::Note),
            ("Gawan mo ako ng flashcards sa trees", Intent::Cards),
            ("Remind me to make a note", Intent::Remind),
            ("Ano ang GWA ko ngayon?", Intent::Grades),
            ("Summarize my notes", Intent::Ask),
            ("Ano ang due ko this week?", Intent::Due),
            ("When is the next quiz?", Intent::Due),
            ("Anong klase ko ngayon?", Intent::Classes),
            ("What's my GWA?", Intent::Grades),
            ("Bagsak ba ako sa Math?", Intent::Grades),
            ("Okay lang ba ako sa Math?", Intent::Ask),
        ] {
            assert_eq!(detect(msg), want, "{msg}");
        }
    }

    #[test]
    fn resolves_days_without_the_model() {
        assert_eq!(THU.weekday(), Weekday::Thursday);
        assert_eq!(resolve_when("remind me bukas", THU), Some(Date::new(2026, 10, 16)));
        assert_eq!(resolve_when("sa Lunes", THU), Some(Date::new(2026, 10, 19)));
        assert_eq!(resolve_when("on Thursday", THU), Some(Date::new(2026, 10, 22)), "same weekday means next week");
        assert_eq!(resolve_when("sa linggo", THU), Some(Date::new(2026, 10, 18)));
        assert_eq!(resolve_when("isang linggo bago ang exam", THU), None, "linggo alone is 'week'");
        assert_eq!(resolve_when("remind me about math", THU), None);
        assert!(is_filipino("Ano ang due ko") && !is_filipino("What is due"));
    }

    #[test]
    fn finds_the_one_subject_a_message_is_about() {
        let subs = |v: &[(&str, &str)]| v.iter().map(|(c, d)| (c.to_string(), d.to_string())).collect::<Vec<_>>();
        let s = subs(&[("MATH 101", "Mathematics in the Modern World"), ("COMP 20073", "Data Structures"), ("COMP 20083", "Calculus for Computing")]);
        assert_eq!(subject_in("Okay lang ba ako sa Math?", &s), Some("MATH 101".into()));
        assert_eq!(subject_in("grade ko sa math101", &s), Some("MATH 101".into()));
        assert_eq!(subject_in("how am i in comp 20073", &s), Some("COMP 20073".into()));
        assert_eq!(subject_in("kumusta ako sa data", &s), None, "short description words are not enough");
        assert_eq!(subject_in("kumusta ako sa calculus", &s), Some("COMP 20083".into()));
        assert_eq!(subject_in("how am i doing in comp", &s), None, "two COMP subjects: ask which");
        assert_eq!(subject_in("how am i doing", &s), None);
    }
}
