//! What the student is asking for, decided by rules, not by the model.
//! Gemma 3 1B answered every "remind me" and "add a note" in words and
//! proposed no action (PR #87's eval), so the rules pick the action and the
//! schema then forces it. The model only writes the reply and fills the text.

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

pub use intportal_core::when::{resolve_when, subject_in, words};

/// Reminders beat cards beat notes: "remind me to make a note" is a reminder.
pub fn detect(msg: &str) -> Intent {
    let w = words(msg);
    let has = |list: &[&str]| w.iter().any(|x| list.contains(&x.as_str()));
    if has(&["remind", "reminder", "paalala", "ipaalala", "alarm"]) {
        Intent::Remind
    } else if has(&["flashcard", "flashcards", "card", "cards"]) || is_quiz(msg) {
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

/// A question that asks to be taught, not told (spec 062 C23): "explain", "walk me through", "step by step".
/// It gets a long answer; every other open question a short one.
pub fn wants_long(msg: &str) -> bool {
    let w = words(msg);
    let joined = format!(" {} ", w.join(" "));
    const WORDS: &[&str] = &["explain", "teach", "summarize", "summarise", "compare", "outline", "detail", "detailed", "elaborate", "ipaliwanag", "turuan", "ituro", "ibuod"];
    const PHRASES: &[&str] = &[" walk me through", " step by step", " in detail", " paano gawin", " how do i solve", " how to solve", " difference between", " pros and cons", " tell me everything", " full explanation", " long answer"];
    w.iter().any(|x| WORDS.contains(&x.as_str())) || PHRASES.iter().any(|p| joined.contains(&format!("{p} ")))
}

/// "Make a quiz on recursion", "gawan mo ako ng quiz sa trees": a quiz to make, not one to look up
/// (spec 062 C18). "When is the next quiz?" names no making verb, so it stays a Due question.
pub fn is_quiz(msg: &str) -> bool {
    let w = words(msg);
    let has = |list: &[&str]| w.iter().any(|x| list.contains(&x.as_str()));
    let at = |list: &[&str]| w.iter().position(|x| list.contains(&x.as_str()));
    // "make a note about the quiz" is a note: the quiz is what the note is about, not what to make.
    let about_a_note = match (at(&["note", "isulat"]), at(&["quiz", "quizzes", "pagsusulit"])) {
        (Some(n), Some(q)) => n < q,
        _ => false,
    };
    has(&["quiz", "quizzes", "pagsusulit"]) && has(&["make", "create", "generate", "write", "build", "gawa", "gawan", "gumawa", "magawa", "quiz me"]) && !about_a_note
}

/// Most cards one request makes; a 1B model's context is the next limit.
pub const CARDS_MAX: usize = 20;
/// Cards made when the student names no number.
pub const CARDS_DEFAULT: usize = 8;

/// The number in front of "cards" ("8 flashcards", "12 na cards", "eight cards"), capped at
/// `CARDS_MAX`. None when the message names none, so the caller picks the default.
pub fn card_count(msg: &str) -> Option<usize> {
    const NAMED: [&str; 12] = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];
    let w = words(msg);
    let n = w.iter().enumerate().filter(|(_, x)| ["flashcard", "flashcards", "card", "cards", "quiz", "question", "questions", "item", "items"].contains(&x.as_str())).find_map(|(i, _)| {
        // "12 na cards", "8 of cards": skip one linking word.
        let before = |k: usize| i.checked_sub(k).map(|j| w[j].as_str());
        let num = |x: &str| x.parse::<usize>().ok().or_else(|| NAMED.iter().position(|n| *n == x).map(|p| p + 1));
        before(1).and_then(num).or_else(|| before(1).filter(|l| ["na", "ng", "of"].contains(l)).and(before(2)).and_then(num))
    })?;
    (n > 0).then_some(n.min(CARDS_MAX))
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

/// A note request that names the chat itself ("make a note of this", "save what we talked about", "gawan mo ng
/// note ito") rather than carrying its own text ("Note: bring calculator", "add a note that the exam moved"):
/// spec 062 C1. Text after a colon is the note's own, so it is never about the chat.
pub fn about_chat(msg: &str) -> bool {
    if msg.split_once(':').is_some_and(|(_, rest)| words(rest).len() >= 2) {
        return false;
    }
    let w = words(msg);
    let joined = format!(" {} ", w.join(" "));
    const PHRASES: &[&str] = &[
        " what we talked", " what we discussed", " what you said", " what you told me", " our chat", " our conversation", " this chat", " this conversation", " the chat", " the conversation", " everything", " all of this", " all that",
        " napag usapan", " napagusapan", " pinag usapan", " pinagusapan", " usapan natin", " sinabi mo",
    ];
    const LAST: &[&str] = &["this", "that", "it", "these", "down", "ito", "iyan", "yan", "iyon", "yun", "yon", "nito", "niyan", "niyon"];
    PHRASES.iter().any(|p| joined.contains(&format!("{p} "))) || w.last().is_some_and(|x| LAST.contains(&x.as_str()))
}

/// True when the message reads as Filipino or Taglish, so the canned reply matches.
/// The language LAR replies in. English for everyone (spec 021 C14): Taglish and Filipino messages are
/// still understood (`is_filipino`, the intents and dates read both), but the reply, the fixed lines
/// and the errors are English. This is the one switch, so Filipino replies can come back in one line.
pub fn replies_in_filipino(_msg: &str) -> bool {
    false
}

pub fn is_filipino(msg: &str) -> bool {
    // "may" is left out on purpose: it is also the English word ("May I see my classes").
    const FIL: &[&str] = &[
        "gumawa", "gawan", "ang", "ano", "ko", "ako", "mo", "ba", "naman", "ngayon", "bukas", "kailan", "klase", "pasahan", "mga", "po", "lang", "salamat", "kumusta", "kamusta", "paano", "pano", "bakit", "sino", "pwede", "hindi", "wala", "yung", "natin",
        // short messages with none of the above ("Ayoko nang mabuhay.", a joke that starts "Anong tawag sa ...")
        "sa", "ng", "nang", "anong", "gaano", "magkano", "saan", "ilang", "ayoko", "ayaw", "gusto", "kasi", "tayo", "namin", "niya", "nalulungkot", "malungkot", "pagod", "dapat", "nasa", "sana", "din", "rin",
    ];
    words(msg).iter().filter(|w| FIL.contains(&w.as_str())).count() >= 1
}

#[cfg(test)]
mod tests {
    use super::*;
    use intportal_core::{model::Weekday, today::Date};

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
            ("Make a quiz on recursion", Intent::Cards),
            ("gawan mo ako ng quiz sa trees", Intent::Cards),
            ("create a 10 item quiz from my notes", Intent::Cards),
            ("Is there a quiz tomorrow?", Intent::Due),
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
    fn a_note_of_the_chat_is_told_from_a_note_with_its_own_text() {
        for msg in ["make a note of this", "Save what we talked about as a note", "note this down", "Gawan mo ng note ito", "isulat mo sa note ang napag-usapan natin", "make a note of our conversation", "can you turn the chat into a note", "jot it down", "note everything you said"] {
            assert!(about_chat(msg), "{msg}");
        }
        for msg in ["Note: bring calculator", "Add a note that Prof. Reyes moved the exam", "make a note: remember this", "Pa-add naman ng note: bring calculator", "add a note to bring my ID"] {
            assert!(!about_chat(msg), "{msg}");
        }
    }

    #[test]
    fn about_chat_reads_the_chat_phrases_in_english_and_taglish() {
        for msg in [
            "save what we discussed", "make a note of what you told me", "put our chat in a note", "note down this conversation", "save all of this as a note", "make a note of all that",
            "gawa ka ng note sa napag usapan", "gawan mo ng note ang napagusapan", "isulat mo ang usapan natin", "i-note mo ang sinabi mo", "gawan mo ako ng note nito", "note this", "write that down", "jot these",
        ] {
            assert!(about_chat(msg), "{msg}");
        }
    }

    #[test]
    fn about_chat_is_not_set_off_by_plain_note_cards_or_reminders() {
        for msg in ["make a note about photosynthesis", "make a note on the chain rule", "remind me", "remind me to pay tuition", "make cards", "make flashcards about trees", "add a note for MATH 101", "create a note about derivatives"] {
            assert!(!about_chat(msg), "{msg}");
        }
    }

    #[test]
    fn about_chat_colon_with_two_words_after_it_is_the_notes_own_text() {
        assert!(!about_chat("note this: bring calculator"), "two words after the colon");
        assert!(!about_chat("make a note of our chat: bring ID tomorrow"));
        assert!(about_chat("make a note of this:"), "nothing after the colon");
        assert!(about_chat("make a note of our chat: ok"), "one word after the colon is not a text");
    }

    #[test]
    fn about_chat_phrases_match_whole_words() {
        assert!(!about_chat("make a note about the chatter"));
        assert!(!about_chat("make a note about all thatch roofs"));
    }

    #[test]
    fn about_chat_only_counts_the_last_word_and_whole_phrases() {
        assert!(!about_chat("it is due friday, make a note about trees"), "'it' not last");
        assert!(about_chat("Make a note of this!"), "punctuation is ignored");
        assert!(about_chat("MAKE A NOTE OF OUR CHAT"));
        assert!(!about_chat(""));
    }

    // #161
    #[test]
    fn the_number_of_cards_asked_for_is_read_in_english_and_filipino() {
        for (msg, want) in [
            ("make 8 flashcards about recursion", Some(8)),
            ("Make 5 cards about recursion", Some(5)),
            ("gumawa ng 8 cards", Some(8)),
            ("gumawa ng 12 na flashcards sa trees", Some(12)),
            ("Gawan mo ako ng 6 na card sa heaps", Some(6)),
            ("make eight flashcards", Some(8)),
            ("make 50 flashcards", Some(20)),
            ("make 0 flashcards", None),
            ("make flashcards about recursion", None),
            ("flashcards for COMP 20073", None),
            ("flashcards for chapter 8", None),
        ] {
            assert_eq!(card_count(msg), want, "{msg}");
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
        for msg in ["Kumusta po", "Wala akong pasahan", "Ano ang GWA ko", "ok lang", "BUKAS ba?", "salamat ha", "Kumusta LAR!", "paano ba?", "Sino ang prof ko"] {
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

    // Spec 062 C18, C23 (part C and D tests).
    #[test]
    fn c18_a_making_word_beside_quiz_makes_a_quiz_and_a_lookup_stays_a_lookup() {
        for msg in ["Make a quiz on recursion", "make me a quiz from my notes", "create a quiz about heaps", "Generate a quiz for MATH 101", "write a quiz on trees", "build a quiz from this note", "gawan mo ako ng quiz sa trees", "gumawa ka ng quiz tungkol sa heaps", "gawa ka ng quiz", "make 5 quizzes", "Make a pagsusulit on trees"] {
            assert!(is_quiz(msg), "{msg}");
            assert_eq!(detect(msg), Intent::Cards, "{msg}");
        }
        for msg in ["When is the next quiz?", "Is there a quiz tomorrow?", "May quiz ba ako bukas?", "What quizzes do I have this week?", "make flashcards on heaps", "quiz", "Kailan ang pagsusulit ko?"] {
            assert!(!is_quiz(msg), "{msg}");
        }
        assert_eq!(detect("When is the next quiz?"), Intent::Due);
    }

    #[test]
    fn c18_a_note_about_a_quiz_is_still_a_note() {
        for msg in ["make a note that the quiz moved to Friday", "Make a note about the quiz", "gumawa ka ng note para sa quiz"] {
            assert_eq!(detect(msg), Intent::Note, "{msg}");
        }
    }

    #[test]
    fn c18_a_reminder_still_beats_a_quiz_and_flashcards_stay_flashcards() {
        assert_eq!(detect("remind me to make a quiz"), Intent::Remind);
        assert_eq!(detect("make flashcards on heaps"), Intent::Cards);
        assert!(!is_quiz("make flashcards on heaps"), "a flashcard deck is not a quiz");
    }

    #[test]
    fn c17_the_number_of_questions_is_read_beside_quiz_questions_and_items() {
        for (msg, want) in [
            ("make a quiz with 10 questions", Some(10)),
            ("make a quiz of 5 items", Some(5)),
            ("quiz me with 6 questions on heaps", Some(6)),
            ("make 12 questions about trees", Some(12)),
            ("gawan mo ako ng 6 na items sa trees", Some(6)),
            ("make 8 quiz questions", Some(8)),
            ("make a quiz of fifty questions", None),
            ("make a quiz with 99 questions", Some(20)),
            ("make a quiz on recursion", None),
        ] {
            assert_eq!(card_count(msg), want, "{msg}");
        }
    }

    #[test]
    fn c17_a_number_before_a_singular_item_or_question_is_read() {
        assert_eq!(card_count("create a 10 item quiz from my notes"), Some(10));
        assert_eq!(card_count("make a 10 question quiz"), Some(10));
    }

    #[test]
    fn c23_a_message_that_asks_to_be_taught_wants_a_long_answer() {
        for msg in [
            "explain recursion",
            "Explain recursion step by step",
            "teach me how heaps work",
            "walk me through binary search",
            "walk me through it",
            "show me step by step how to solve 2x + 3 = 11",
            "how do I solve a quadratic equation",
            "what is the difference between a stack and a queue",
            "summarize chapter 3 in detail",
            "give me an outline of the French Revolution",
            "compare BFS and DFS",
            "Can you please elaborate on that",
            "paki-explain mo naman ang recursion",
            "ipaliwanag mo ang heaps",
            "turuan mo ako ng recursion",
            "ituro mo sa akin ang binary search",
            "paano gawin ang long division",
            "ibuod mo ang chapter 2",
            "explain mo nga ang pointers, step by step",
            "EXPLAIN RECURSION!!!",
            "tell me everything about the Katipunan",
        ] {
            assert!(wants_long(msg), "{msg}");
        }
    }

    #[test]
    fn c23_a_short_question_wants_a_short_answer() {
        for msg in [
            "what is a stack?",
            "who is Jose Rizal",
            "what's the capital of France?",
            "define heap",
            "ano ang GWA ko",
            "kailan ang quiz ko",
            "when did the Philippines become independent",
            "is a tomato a fruit",
            "who is my teacher",
            "what does explanatory mean",
            "How many credits is COMP 20073?",
            "hi",
            "",
        ] {
            assert!(!wants_long(msg), "{msg}");
        }
    }
}
