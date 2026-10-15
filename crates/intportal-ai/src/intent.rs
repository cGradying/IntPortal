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

/// Like `detect`, knowing whether a note is open. Asking about the open note
/// ("Summarize this note") is a question for the model with the note as context,
/// not a request to add a note; "add a note: ..." still is.
pub fn resolve(msg: &str, note_open: bool) -> Intent {
    let intent = detect(msg);
    if intent != Intent::Note || !note_open {
        return intent;
    }
    let w = words(msg);
    let has = |list: &[&str]| w.iter().any(|x| list.contains(&x.as_str()));
    let reads = has(&["summarize", "summarise", "summary", "review", "explain", "what", "how", "why", "tell", "quiz", "ibuod", "buod", "ipaliwanag", "paliwanag", "ano", "anong", "paano", "bakit", "laman"]);
    let writes = has(&["add", "create", "make", "save", "write", "new", "jot", "isulat", "idagdag", "magdagdag", "gumawa", "gawa", "lagyan"]);
    if reads && !writes { Intent::Ask } else { intent }
}

/// True when the message reads as Filipino or Taglish, so the canned reply matches.
pub fn is_filipino(msg: &str) -> bool {
    // "may" is left out on purpose: it is also the English word ("May I see my classes").
    const FIL: [&str; 15] = ["ang", "ano", "ko", "ako", "mo", "ba", "naman", "ngayon", "bukas", "kailan", "klase", "pasahan", "mga", "po", "lang"];
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
    let key = |c: &str| c.to_lowercase().replace(' ', "");
    let hits: Vec<&String> = subjects.iter().map(|(c, _)| c).filter(|c| squashed.contains(&key(c))).collect();
    // "math 101" also contains "math1": the longer code is the one named.
    let by_code = hits.iter().copied().filter(|c| !hits.iter().any(|o| key(o) != key(c) && key(o).contains(&key(c)))).collect();
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
    fn questions_about_the_open_note_are_asks_but_note_requests_stay_notes() {
        for msg in ["Summarize this note", "What should I review from this note?", "ibuod ang note na ito", "Ano ang laman ng note na ito?", "Paano ko ire-review ang note na ito"] {
            assert_eq!(resolve(msg, true), Intent::Ask, "{msg}");
            assert_eq!(resolve(msg, false), Intent::Note, "no note open: {msg}");
        }
        for msg in ["Add a note: bring calculator", "Pa-add naman ng note: bring calculator", "Isulat mo sa note: bring ID", "make a note that the exam moved", "Note: bring calculator"] {
            assert_eq!(resolve(msg, true), Intent::Note, "{msg}");
        }
        assert_eq!(resolve("remind me about this note", true), Intent::Remind);
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

    // C10: the rules, not the model, pick the action.
    #[test]
    fn taglish_phrasings_reach_the_right_action() {
        for (msg, want) in [
            ("Paalala mo ako bukas", Intent::Remind),
            ("Ipaalala mo sa akin ang bayad", Intent::Remind),
            ("set an alarm for 6am", Intent::Remind),
            ("Isulat mo: bring ID", Intent::Note),
            ("May quiz ba ako bukas?", Intent::Due),
            ("Kailan ang pasahan ng takdang-aralin?", Intent::Due),
            ("Anong deadlines ko this week", Intent::Due),
            ("Ano'ng schedule ko ngayon?", Intent::Classes),
            ("Iskedyul ko bukas?", Intent::Classes),
            ("May klase ba kami?", Intent::Classes),
            ("Pasado ba ako?", Intent::Grades),
            ("Passing ba ako sa Math?", Intent::Grades),
            ("magkano average ko", Intent::Grades),
            ("What is my GPA", Intent::Grades),
            ("Kumusta ang standing ko?", Intent::Grades),
        ] {
            assert_eq!(detect(msg), want, "{msg}");
        }
    }

    #[test]
    fn detection_ignores_case_hyphens_and_punctuation() {
        for msg in ["REMIND ME", "i-remind mo", "Mag-remind!!", "remind,me", "(remind)"] {
            assert_eq!(detect(msg), Intent::Remind, "{msg}");
        }
    }

    #[test]
    fn earlier_rules_win_when_a_message_has_several_words() {
        assert_eq!(detect("remind me about the flashcards"), Intent::Remind);
        assert_eq!(detect("flashcards for the quiz"), Intent::Cards);
        assert_eq!(detect("note about the quiz"), Intent::Note);
        assert_eq!(detect("which class has the exam"), Intent::Due, "due words come before classes");
        assert_eq!(detect("grade in my class"), Intent::Classes, "classes come before grades");
    }

    #[test]
    fn only_whole_words_trigger_an_action() {
        for msg in ["notebook shopping", "I love cardio", "the passage was long", "a classic", "duet practice", "noted, thanks", "compass"] {
            assert_eq!(detect(msg), Intent::Ask, "{msg}");
        }
    }

    #[test]
    fn open_questions_fall_through_to_ask() {
        for msg in ["How do I focus?", "Paano mag-aral nang mabilis?", "Explain binary trees", "hello", "Summarize my notes", "Okay lang ba ako sa Math?"] {
            assert_eq!(detect(msg), Intent::Ask, "{msg}");
        }
    }

    #[test]
    fn empty_emoji_and_huge_messages_do_not_panic() {
        assert_eq!(detect(""), Intent::Ask);
        assert_eq!(detect("   \n\t "), Intent::Ask);
        assert_eq!(detect("😀😀😀"), Intent::Ask);
        assert_eq!(detect("🔔remind🔔me🔔"), Intent::Remind, "emoji separate words like punctuation");
        assert_eq!(detect("📝 note"), Intent::Note);
        let long = format!("{} grades", "blah ".repeat(20_000));
        assert_eq!(detect(&long), Intent::Grades);
        assert_eq!(detect(&"é".repeat(50_000)), Intent::Ask);
        assert!(!is_filipino("") && !is_filipino("😀"));
        assert_eq!(resolve_when("", THU), None);
        assert_eq!(resolve_when("😀", THU), None);
        assert_eq!(subject_in("😀", &[("MATH 101".into(), "Mathematics".into())]), None);
    }

    #[test]
    fn filipino_is_spotted_by_any_one_marker_word() {
        for msg in ["Kumusta po", "Wala akong pasahan", "Ano ang GWA ko", "ok lang", "BUKAS ba?"] {
            assert!(is_filipino(msg), "{msg}");
        }
        for msg in ["Hello there", "What is due this week", "Summarize my notes", "go"] {
            assert!(!is_filipino(msg), "{msg}");
        }
        assert!(!is_filipino("May I see my classes") && !is_filipino("may"), "English \"may\" is not a marker");
        assert!(is_filipino("May pasahan ba ako") && is_filipino("may klase bukas"), "\"may\" with real markers still reads Filipino");
        assert!(!is_filipino("kobe"), "markers are whole words, not substrings");
    }

    #[test]
    fn every_weekday_name_resolves_to_its_next_date() {
        for (msg, want) in [
            ("on monday", 19),
            ("sa Martes", 20),
            ("tuesday", 20),
            ("miyerkules", 21),
            ("wednesday", 21),
            ("huwebes", 22),
            ("friday", 16),
            ("biyernes", 16),
            ("sa sabado", 17),
            ("saturday", 17),
            ("sunday", 18),
            ("sa Linggo", 18),
        ] {
            assert_eq!(resolve_when(msg, THU), Some(Date::new(2026, 10, want)), "{msg}");
        }
    }

    #[test]
    fn named_days_are_case_blind_and_the_first_one_wins() {
        assert_eq!(resolve_when("BUKAS", THU), Some(Date::new(2026, 10, 16)));
        assert_eq!(resolve_when("today", THU), Some(THU));
        assert_eq!(resolve_when("mamaya", THU), Some(THU));
        assert_eq!(resolve_when("ngayon", THU), Some(THU));
        assert_eq!(resolve_when("makalawa", THU), Some(Date::new(2026, 10, 17)));
        assert_eq!(resolve_when("bukas sa lunes", THU), Some(Date::new(2026, 10, 16)));
        assert_eq!(resolve_when("lunes bukas", THU), Some(Date::new(2026, 10, 19)));
        assert_eq!(resolve_when("linggo", THU), None, "a lone linggo is a week");
        assert_eq!(resolve_when("tomorrowland", THU), None, "whole words only");
    }

    #[test]
    fn days_roll_over_month_and_year_ends() {
        let fri_oct_30 = Date::new(2026, 10, 30);
        assert_eq!(fri_oct_30.weekday(), Weekday::Friday);
        assert_eq!(resolve_when("tomorrow", fri_oct_30), Some(Date::new(2026, 10, 31)));
        assert_eq!(resolve_when("monday", fri_oct_30), Some(Date::new(2026, 11, 2)));
        let new_years_eve = Date::new(2026, 12, 31);
        assert_eq!(resolve_when("bukas", new_years_eve), Some(Date::new(2027, 1, 1)));
        assert_eq!(resolve_when("makalawa", new_years_eve), Some(Date::new(2027, 1, 2)));
    }

    fn subs(v: &[(&str, &str)]) -> Vec<(String, String)> {
        v.iter().map(|(c, d)| (c.to_string(), d.to_string())).collect()
    }

    #[test]
    fn a_subject_is_found_by_code_letters_or_description_word() {
        let s = subs(&[("MATH 101", "Mathematics in the Modern World"), ("COMP 20073", "Data Structures"), ("ENGL 100", "Purposive Communication")]);
        assert_eq!(subject_in("Math", &s), Some("MATH 101".into()), "letters of the code");
        assert_eq!(subject_in("MATH", &s), Some("MATH 101".into()));
        assert_eq!(subject_in("how is math 101 going", &s), Some("MATH 101".into()), "spaced code");
        assert_eq!(subject_in("how is Math101 going", &s), Some("MATH 101".into()), "squashed code");
        assert_eq!(subject_in("comp20073?", &s), Some("COMP 20073".into()));
        assert_eq!(subject_in("kumusta ako sa structures", &s), Some("COMP 20073".into()), "description word of 5+ letters");
        assert_eq!(subject_in("kumusta ako sa COMMUNICATION", &s), Some("ENGL 100".into()));
        assert_eq!(subject_in("GRADE KO SA ENGL", &s), Some("ENGL 100".into()));
    }

    #[test]
    fn ambiguous_or_unknown_subjects_name_nothing() {
        let two_maths = subs(&[("MATH 101", "Mathematics"), ("MATH 102", "Calculus")]);
        assert_eq!(subject_in("how am i in math", &two_maths), None, "two MATH subjects");
        assert_eq!(subject_in("how am i in math 102", &two_maths), Some("MATH 102".into()), "the full code settles it");
        let nested = subs(&[("MATH 1", "Algebra"), ("MATH 101", "Calculus")]);
        assert_eq!(subject_in("grade in math 101", &nested), Some("MATH 101".into()), "the longer code wins");
        assert_eq!(subject_in("grade in math 1", &nested), Some("MATH 1".into()));
        assert_eq!(subject_in("how am i in math", &nested), None, "still ambiguous");
        let shared = subs(&[("MATH 101", "Mathematics in the Modern World"), ("PHYS 101", "Physics in the Modern World")]);
        assert_eq!(subject_in("modern world grade", &shared), None, "a shared description word");
        assert_eq!(subject_in("how am i in history", &shared), None);
        assert_eq!(subject_in("anything", &[]), None);
        assert_eq!(subject_in("", &shared), None);
    }

    #[test]
    fn short_code_letters_do_not_match_by_themselves() {
        let s = subs(&[("PE 1", "Physical Education"), ("NS 2", "Nat Sci")]);
        assert_eq!(subject_in("how is pe doing", &s), None, "two-letter codes are too easy to hit by accident");
        assert_eq!(subject_in("grade sa pe 1", &s), Some("PE 1".into()), "the full code works");
        assert_eq!(subject_in("physical", &s), Some("PE 1".into()), "a long description word is enough");
    }
}
