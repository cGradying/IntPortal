//! IntAssis: one chat turn. It answers from the student's own facts and, when
//! the message asks for something, proposes ONE action for the student to
//! confirm. Nothing here writes: the UI shows a card and Apply calls the
//! existing commands (`set_note`, `set_plan`, `save_deck`).
use crate::{
    intent::{detect, is_filipino, resolve_when, subject_in, Intent},
    llm::Llm,
    prompt::{build, Section, Template},
    reply::{self, ReplyStream},
};
use intportal_core::today::Date;
use serde_json::{json, Value};

/// What IntAssis may know, already formatted by the caller from core data
/// (classes today, deadlines, grade standing, the open note, search hits).
#[derive(Default)]
pub struct Facts {
    pub today: Option<Date>,
    pub classes_today: Vec<String>,
    /// "Quiz 2: COMP 20073, Fri 2026-10-16"
    pub due: Vec<String>,
    /// "COMP 20073: 86% so far, needs 78% on the rest for 1.75"
    pub standing: Vec<String>,
    pub open_note: Option<String>,
    pub hits: Vec<String>,
    /// Subject codes the student has; the only values an action may name.
    pub subjects: Vec<String>,
    /// (code, description) of the same subjects, to tell which one a message means.
    pub subject_names: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Proposal {
    AddNote { subject: Option<String>, text: String },
    SetReminder { date: Date, text: String },
    MakeCards { topic: String },
}

#[derive(Debug, PartialEq)]
pub struct Answer {
    pub reply: String,
    pub proposal: Option<Proposal>,
}

const SYSTEM: &str = "You are IntAssis, a calm study helper inside a student's schedule app (PUP, Philippines). \
Answer from the facts below only; if they do not say, say you do not know. Keep it to 1-3 short sentences. \
Reply in the language the student used (English, Filipino or Taglish). Never invent dates, grades or subjects. Reply as JSON.";

fn schema(intent: Intent, subjects: &[String], ask_when: bool) -> Value {
    let mut props = json!({});
    let extra: Vec<(&str, Value)> = match intent {
        Intent::Ask | Intent::Due | Intent::Classes | Intent::Grades => vec![],
        Intent::Note => {
            let mut subs: Vec<&str> = subjects.iter().map(String::as_str).collect();
            subs.push("none");
            vec![("text", json!({"type": "string"})), ("subject", json!({"enum": subs}))]
        }
        Intent::Remind => {
            let mut v = vec![("text", json!({"type": "string"}))];
            if ask_when {
                v.push(("when", json!({"enum": (0..14).map(|n| format!("d{n}")).collect::<Vec<_>>()})));
            }
            v
        }
        Intent::Cards => vec![("topic", json!({"type": "string"}))],
    };
    if intent == Intent::Ask {
        props["reply"] = json!({"type": "string"});
    }
    let mut req: Vec<String> = props.as_object().map_or(vec![], |o| o.keys().cloned().collect());
    for (k, v) in extra {
        props[k] = v;
        req.push(k.to_string());
    }
    json!({"type": "object", "properties": props, "required": req})
}

/// Exact answers from the app's own data, in the student's language. None
/// when the data is empty for a kind of question the app can't answer: the
/// model then answers from whatever facts there are, or says it doesn't know.
fn canned(intent: Intent, f: &Facts, fil: bool, subject: Option<&str>) -> Option<String> {
    let lines = |head: &str, v: &[String]| format!("{head}\n{}", v.iter().map(|x| format!("- {x}")).collect::<Vec<_>>().join("\n"));
    match intent {
        Intent::Due if f.due.is_empty() => Some(if fil { "Wala kang due sa susunod na mga araw." } else { "Nothing is due in the next few days." }.into()),
        Intent::Due => Some(lines(if fil { "Paparating:" } else { "Coming up:" }, &f.due)),
        Intent::Classes if f.classes_today.is_empty() => Some(if fil { "Wala kang klase ngayon." } else { "You have no classes today." }.into()),
        Intent::Classes => Some(lines(if fil { "Mga klase mo ngayon:" } else { "Your classes today:" }, &f.classes_today)),
        Intent::Grades if subject.is_some() => {
            let code = subject.unwrap_or_default();
            let mine: Vec<String> = f.standing.iter().filter(|l| l.starts_with(&format!("{code}:"))).cloned().collect();
            Some(if mine.is_empty() {
                if fil { format!("Wala pang grading para sa {code}. I-set up ito sa syllabus ng subject.") } else { format!("No grading is set up for {code} yet. Add it in the subject's syllabus.") }
            } else {
                lines(if fil { "Standing mo:" } else { "Where you stand:" }, &mine)
            })
        }
        Intent::Grades if f.standing.is_empty() => Some(if fil { "Wala pang grades na maipapakita. I-set up ang grading sa syllabus ng subject para masubaybayan ko." } else { "No grades to show yet. Set up a subject's grading in its syllabus and I can track where you stand." }.into()),
        Intent::Grades => Some(lines(if fil { "Standing mo:" } else { "Where you stand:" }, &f.standing)),
        _ => None,
    }
}

fn date_table(today: Date) -> String {
    (0..14).map(|n| { let d = today.add_days(n); format!("d{n} = {:?} {d}{}\n", d.weekday(), if n == 0 { " (today)" } else { "" }) }).collect()
}

/// `history` is (student, intassis) pairs, oldest first; only the last few fit.
pub fn answer(llm: &mut dyn Llm, tpl: Template, facts: &Facts, history: &[(String, String)], msg: &str) -> Result<Answer, String> {
    answer_streaming(llm, tpl, facts, history, msg, &mut |_| ())
}

/// Like `answer`, and `on_text` gets the words of an open question's reply as
/// the model writes them. Requests are short and are shown as a confirm card.
pub fn answer_streaming(llm: &mut dyn Llm, tpl: Template, facts: &Facts, history: &[(String, String)], msg: &str, on_text: &mut dyn FnMut(&str)) -> Result<Answer, String> {
    let today = facts.today.ok_or("today is unknown")?;
    let msg: String = msg.chars().take(500).collect(); // an essay must not push the facts out of the window
    let msg = msg.as_str();
    let intent = detect(msg);
    let subject = subject_in(msg, &facts.subject_names);
    if let Some(reply) = canned(intent, facts, is_filipino(msg), subject.as_deref()) {
        return Ok(Answer { reply, proposal: None });
    }
    let when = resolve_when(msg, today);
    let ask_when = intent == Intent::Remind && when.is_none();

    let list = |v: &[String]| v.iter().map(|s| format!("- {s}\n")).collect::<String>();
    let recent: String = history.iter().rev().take(4).rev().map(|(s, a)| format!("Student: {s}\nIntAssis: {a}\n")).collect();
    let about = subject.as_ref().map(|c| format!("{c} {}", facts.subject_names.iter().find(|(k, _)| k == c).map_or("", |(_, d)| d.as_str()))).unwrap_or_default();
    let (classes, due, standing, note, hits, dates, chat) = (
        list(&facts.classes_today),
        list(&facts.due),
        list(&facts.standing),
        facts.open_note.clone().unwrap_or_default(),
        list(&facts.hits),
        if ask_when { date_table(today) } else { String::new() },
        recent,
    );
    let sections = [
        Section { title: "Today", body: &format!("{today} ({:?})\n{classes}", today.weekday()), priority: 9 },
        Section { title: "The student is asking about", body: &about, priority: 9 },
        Section { title: "Coming up", body: &due, priority: 8 },
        Section { title: "Grades", body: &standing, priority: 5 },
        Section { title: "Dates (pick one id)", body: &dates, priority: 9 },
        Section { title: "Open note", body: &note, priority: 6 },
        Section { title: "From the student's notes", body: &hits, priority: 7 },
        Section { title: "Conversation so far", body: &chat, priority: 4 },
    ];
    // A request gets no facts: with them a 1B model starts chatting inside `text`.
    let live: Vec<_> = sections.into_iter().filter(|s| !s.body.trim().is_empty() && (matches!(intent, Intent::Ask) || s.title.starts_with("Dates"))).collect();
    let task = match intent {
        Intent::Ask | Intent::Due | Intent::Classes | Intent::Grades => "",
        Intent::Note => "\nThe student wants a note saved. In `text` put only the note itself, under 15 words, no reply. Example: \"Pa-add ng note: bring calculator sa quiz\" -> text \"Bring calculator to the quiz\".",
        Intent::Remind => "\nThe student wants a reminder. In `text` put only the thing to be reminded of, under 10 words, no reply. Example: \"remind me to pay tuition on Monday\" -> text \"Pay tuition\".",
        Intent::Cards => "\nThe student wants flashcards. In `topic` put the topic.",
    };
    let prompt = tpl.wrap(&build(&format!("{SYSTEM}{task}"), &live, 7000), &format!("Student: {msg}"));
    let mut stream = ReplyStream::default();
    let raw = llm.generate(&prompt, Some(&schema(intent, &facts.subjects, ask_when)), 300, &mut |piece| {
        if intent == Intent::Ask {
            if let Some(words) = stream.feed(piece) {
                on_text(&words);
            }
        }
        true
    })?;
    let v: Value = reply::parse(&raw).map_err(|e| e.to_string())?;
    let s = |k: &str| v[k].as_str().unwrap_or("").trim().to_string();
    let text: String = s("text").chars().take(120).collect::<String>().trim_end_matches(['.', ' ']).to_string();
    let proposal = match intent {
        Intent::Ask | Intent::Due | Intent::Classes | Intent::Grades => None,
        _ if text.is_empty() && intent != Intent::Cards => None,
        Intent::Note => Some(Proposal::AddNote { subject: Some(s("subject")).filter(|x| facts.subjects.contains(x)), text }),
        Intent::Remind => {
            let date = when.or_else(|| s("when").strip_prefix('d').and_then(|n| n.parse::<i64>().ok()).filter(|n| (0..14).contains(n)).map(|n| today.add_days(n)));
            date.map(|date| Proposal::SetReminder { date, text })
        }
        Intent::Cards => Some(Proposal::MakeCards { topic: s("topic") }).filter(|p| matches!(p, Proposal::MakeCards { topic } if !topic.is_empty())),
    };
    let fil = is_filipino(msg);
    let reply = match (&proposal, intent) {
        (Some(p), _) => confirm(p, fil),
        (None, Intent::Ask) => s("reply"),
        (None, _) => if fil { "Hindi ko nakuha iyon. Pwede mo bang ulitin?" } else { "I didn't catch that. Could you say it again?" }.into(),
    };
    Ok(Answer { reply, proposal })
}

/// What the chat shows when something fails, in the student's language. The
/// raw error is for logs, not for a student.
pub fn friendly(error: &str, fil: bool) -> String {
    // A sentence written for the student ("Select the words to explain first.") passes through.
    if error.ends_with('.') || error.ends_with('?') {
        return error.into();
    }
    let (en, tl) = if error.contains("busy") {
        ("I'm still working on your last message. Give me a second.", "Ginagawa ko pa ang huli mong mensahe. Sandali lang.")
    } else if error.contains("first") || error.contains("Download the model") {
        ("Turn IntAssis on first, in the You tab.", "I-on muna ang IntAssis sa You tab.")
    } else if error.contains("does not fit") {
        ("That was too long for me. Try a shorter question.", "Masyadong mahaba iyon para sa akin. Subukan ang mas maikling tanong.")
    } else if error.contains("memory") {
        ("This phone doesn't have enough free memory right now. Close other apps and try again.", "Kulang ang libreng memory ng phone ngayon. Isara ang ibang apps at subukan ulit.")
    } else if error.contains("JSON") {
        ("My words got tangled. Ask me again?", "Nagulo ang sagot ko. Pwede mo bang ulitin?")
    } else {
        ("Something went wrong. Try again.", "May nangyaring mali. Subukan ulit.")
    };
    if fil { tl } else { en }.into()
}

/// What the confirm card says; in Rust so it is always short, right and in the student's language.
fn confirm(p: &Proposal, fil: bool) -> String {
    match (p, fil) {
        (Proposal::SetReminder { text, .. }, false) => format!("Reminder ready: {text}. Confirm to save it."),
        (Proposal::SetReminder { text, .. }, true) => format!("Handa na ang paalala: {text}. I-confirm para i-save."),
        (Proposal::AddNote { subject, text }, false) => format!("Note ready{}: {text}. Confirm to save it.", subject.as_ref().map(|s| format!(" for {s}")).unwrap_or_default()),
        (Proposal::AddNote { subject, text }, true) => format!("Handa na ang note{}: {text}. I-confirm para i-save.", subject.as_ref().map(|s| format!(" sa {s}")).unwrap_or_default()),
        (Proposal::MakeCards { topic }, false) => format!("I'll make flashcards on {topic}. Confirm to start."),
        (Proposal::MakeCards { topic }, true) => format!("Gagawa ako ng flashcards sa {topic}. I-confirm para magsimula."),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    const THU: Date = Date { y: 2026, m: 10, d: 15 };

    fn facts() -> Facts {
        Facts {
            today: Some(THU),
            classes_today: vec!["COMP 20073 9:00".into()],
            due: vec!["Quiz 2: COMP 20073, Fri 2026-10-16".into()],
            subjects: vec!["COMP 20073".into(), "MATH 101".into()],
            ..Facts::default()
        }
    }

    #[test]
    fn a_reminder_request_forces_a_reminder_with_a_rust_resolved_date() {
        let mut m = FakeLlm::new(&[r#"{"reply":"Sige, ready na.","text":"Math 101 assignment"}"#]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "Pwede mo ba akong i-remind bukas about Math 101 assignment?").unwrap();
        assert_eq!(a.proposal, Some(Proposal::SetReminder { date: Date::new(2026, 10, 16), text: "Math 101 assignment".into() }));
        assert_eq!(a.reply, "Handa na ang paalala: Math 101 assignment. I-confirm para i-save.");
        assert!(!m.prompts[0].contains("pick one id"), "a day the message names needs no date table");
    }

    #[test]
    fn an_unclear_day_makes_the_model_pick_from_ids_and_a_bad_id_gives_no_proposal() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok","text":"submit","when":"d3"}"#, r#"{"reply":"ok","text":"submit","when":"d40"}"#]);
        let a = answer(&mut m, Template::ChatMl, &facts(), &[], "remind me to submit the report").unwrap();
        assert_eq!(a.proposal, Some(Proposal::SetReminder { date: Date::new(2026, 10, 18), text: "submit".into() }));
        assert!(m.prompts[0].contains("d3 = Sunday 2026-10-18"));
        assert_eq!(answer(&mut m, Template::ChatMl, &facts(), &[], "remind me to submit").unwrap().proposal, None);
    }

    #[test]
    fn a_note_keeps_only_a_real_subject() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok","text":"bring calculator","subject":"MATH 101"}"#, r#"{"reply":"ok","text":"x","subject":"none"}"#]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "Add a note: bring calculator").unwrap();
        assert_eq!(a.proposal, Some(Proposal::AddNote { subject: Some("MATH 101".into()), text: "bring calculator".into() }));
        let b = answer(&mut m, Template::Gemma, &facts(), &[], "add a note x").unwrap();
        assert_eq!(b.proposal, Some(Proposal::AddNote { subject: None, text: "x".into() }));
    }

    #[test]
    fn a_question_gets_facts_and_no_proposal() {
        let mut m = FakeLlm::new(&[r#"{"reply":"May quiz ka bukas sa COMP 20073."}"#]);
        let hist = vec![("hi".to_string(), "hello".to_string())];
        let a = answer(&mut m, Template::Gemma, &facts(), &hist, "Paano ako magfo-focus sa pag-aaral?").unwrap();
        assert_eq!(a.proposal, None);
        assert!(m.prompts[0].contains("Quiz 2: COMP 20073, Fri 2026-10-16") && m.prompts[0].contains("Student: hi"));
    }

    #[test]
    fn app_data_questions_are_answered_exactly_without_the_model() {
        let mut m = FakeLlm::new(&[]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "Ano ang due ko this week?").unwrap();
        assert_eq!(a.reply, "Paparating:\n- Quiz 2: COMP 20073, Fri 2026-10-16");
        let b = answer(&mut m, Template::Gemma, &facts(), &[], "What classes do I have today?").unwrap();
        assert_eq!(b.reply, "Your classes today:\n- COMP 20073 9:00");
        let none = Facts { today: Some(THU), ..Facts::default() };
        assert_eq!(answer(&mut m, Template::Gemma, &none, &[], "anong klase ko ngayon").unwrap().reply, "Wala kang klase ngayon.");
        assert!(m.prompts.is_empty());
    }

    #[test]
    fn cards_need_a_topic() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok","topic":"binary trees"}"#]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "gawan mo ako ng flashcards sa trees").unwrap();
        assert_eq!(a.proposal, Some(Proposal::MakeCards { topic: "binary trees".into() }));
    }

    #[test]
    fn notes_reach_an_open_question_but_never_a_request() {
        let f = Facts { hits: vec!["MATH 101: the chain rule multiplies derivatives".into()], open_note: Some("Quiz topics: limits".into()), ..facts() };
        let mut m = FakeLlm::new(&[r#"{"reply":"Multiply the derivatives."}"#, r#"{"reply":"ok","text":"pay tuition"}"#]);
        answer(&mut m, Template::Gemma, &f, &[], "ano ang chain rule?").unwrap();
        assert!(m.prompts[0].contains("From the student's notes") && m.prompts[0].contains("chain rule multiplies") && m.prompts[0].contains("Quiz topics: limits"));
        answer(&mut m, Template::Gemma, &f, &[], "remind me bukas to pay tuition").unwrap();
        assert!(!m.prompts[1].contains("chain rule"), "a request gets no facts");
    }

    #[test]
    fn an_open_reply_streams_word_by_word_and_a_request_does_not() {
        let mut m = FakeLlm::new(&[r#"{"reply":"May quiz ka bukas."}"#, r#"{"reply":"ok","text":"pay tuition"}"#]);
        let mut seen = String::new();
        let a = answer_streaming(&mut m, Template::Gemma, &facts(), &[], "paano mag-aral?", &mut |w| seen.push_str(w)).unwrap();
        assert_eq!((seen.as_str(), a.reply.as_str()), ("May quiz ka bukas.", "May quiz ka bukas."));
        let mut seen2 = String::new();
        answer_streaming(&mut m, Template::Gemma, &facts(), &[], "remind me bukas to pay tuition", &mut |w| seen2.push_str(w)).unwrap();
        assert!(seen2.is_empty());
    }

    #[test]
    fn a_grade_question_names_its_subject_and_empty_grades_get_a_plain_answer() {
        let mut m = FakeLlm::new(&[]);
        let f = Facts {
            standing: vec!["MATH 101: 86% so far".into(), "COMP 20073: 70% so far".into()],
            subject_names: vec![("MATH 101".into(), "Mathematics".into()), ("COMP 20073".into(), "Data Structures".into()), ("ENGL 100".into(), "English".into())],
            ..facts()
        };
        assert_eq!(answer(&mut m, Template::Gemma, &f, &[], "Bagsak ba ako sa Math?").unwrap().reply, "Standing mo:\n- MATH 101: 86% so far");
        assert_eq!(answer(&mut m, Template::Gemma, &f, &[], "what is my grade in english").unwrap().reply, "No grading is set up for ENGL 100 yet. Add it in the subject's syllabus.");
        let none = Facts { today: Some(THU), ..Facts::default() };
        assert!(answer(&mut m, Template::Gemma, &none, &[], "what's my GWA?").unwrap().reply.starts_with("No grades to show yet"));
        assert!(m.prompts.is_empty(), "exact answers never reach the model");
    }

    #[test]
    fn an_open_question_is_told_which_subject_it_is_about() {
        let f = Facts { subject_names: vec![("MATH 101".into(), "Mathematics".into())], standing: vec!["MATH 101: 86% so far".into()], ..facts() };
        let mut m = FakeLlm::new(&[r#"{"reply":"Okay ka, 86%."}"#]);
        answer(&mut m, Template::Gemma, &f, &[], "Okay lang ba ako sa Math?").unwrap();
        assert!(m.prompts[0].contains("The student is asking about\nMATH 101 Mathematics"));
    }

    #[test]
    fn errors_reach_the_student_in_plain_words() {
        assert_eq!(friendly("prompt of 5000 tokens does not fit 4096 context", false), "That was too long for me. Try a shorter question.");
        assert_eq!(friendly("the reply has no JSON object", true), "Nagulo ang sagot ko. Pwede mo bang ulitin?");
        assert!(!friendly("reqwest: connection reset", false).contains("reqwest"));
        assert_eq!(friendly("Select the words to explain first.", true), "Select the words to explain first.");
    }

    fn rich() -> Facts {
        Facts {
            standing: vec!["MATH 101: 86% so far".into(), "COMP 20073: 70% so far".into()],
            subject_names: vec![("MATH 101".into(), "Mathematics".into()), ("COMP 20073".into(), "Data Structures".into()), ("ENGL 100".into(), "English".into())],
            ..facts()
        }
    }

    fn bare() -> Facts {
        Facts { today: Some(THU), ..Facts::default() }
    }

    fn reply_of(f: &Facts, msg: &str) -> String {
        answer(&mut FakeLlm::new(&[]), Template::Gemma, f, &[], msg).unwrap().reply
    }

    /// Hands back what it was given, as a model that was told to stop would.
    struct Cut(&'static [&'static str]);

    impl Llm for Cut {
        fn generate(&mut self, _p: &str, _s: Option<&Value>, _m: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
            let mut out = String::new();
            for p in self.0 {
                out.push_str(p);
                if !on_token(p) {
                    break;
                }
            }
            Ok(out)
        }

        fn embed(&mut self, _t: &[&str]) -> Result<Vec<Vec<f32>>, String> {
            Ok(vec![])
        }
    }

    // C10: schedule and grades questions never reach the model, in either language.
    #[test]
    fn empty_schedule_and_deadlines_are_answered_plainly_in_both_languages() {
        let f = bare();
        for (msg, want) in [
            ("what is due this week", "Nothing is due in the next few days."),
            ("Ano ang due ko ngayon", "Wala kang due sa susunod na mga araw."),
            ("do i have classes today", "You have no classes today."),
            ("may klase ba ako ngayon", "Wala kang klase ngayon."),
            ("When is my next exam?", "Nothing is due in the next few days."),
            ("Kailan ang pasahan ko?", "Wala kang due sa susunod na mga araw."),
        ] {
            assert_eq!(reply_of(&f, msg), want, "{msg}");
        }
    }

    #[test]
    fn empty_grades_get_a_plain_answer_not_a_made_up_one() {
        let f = bare();
        let en = reply_of(&f, "what's my GWA?");
        let tl = reply_of(&f, "ano ang GWA ko?");
        assert_eq!(en, "No grades to show yet. Set up a subject's grading in its syllabus and I can track where you stand.");
        assert_eq!(tl, "Wala pang grades na maipapakita. I-set up ang grading sa syllabus ng subject para masubaybayan ko.");
        for r in [&en, &tl] {
            assert!(!r.contains('%') && !r.contains("\n- "), "{r}");
        }
        // A subject that has no grading in the list says so, in the student's language.
        let f = Facts { standing: vec!["MATH 101: 86% so far".into()], ..rich() };
        assert_eq!(reply_of(&f, "ano ang grade ko sa english"), "Wala pang grading para sa ENGL 100. I-set up ito sa syllabus ng subject.");
    }

    #[test]
    fn listed_facts_come_back_in_order_under_a_heading_in_the_students_language() {
        let f = Facts {
            classes_today: vec!["COMP 20073 9:00".into(), "MATH 101 13:00".into()],
            due: vec!["Quiz 2: COMP 20073, Fri 2026-10-16".into(), "Essay: ENGL 100, Mon 2026-10-19".into()],
            ..rich()
        };
        assert_eq!(reply_of(&f, "anong klase ko ngayon"), "Mga klase mo ngayon:\n- COMP 20073 9:00\n- MATH 101 13:00");
        assert_eq!(reply_of(&f, "which classes today"), "Your classes today:\n- COMP 20073 9:00\n- MATH 101 13:00");
        assert_eq!(reply_of(&f, "may pasahan ba ako"), "Paparating:\n- Quiz 2: COMP 20073, Fri 2026-10-16\n- Essay: ENGL 100, Mon 2026-10-19");
        assert_eq!(reply_of(&f, "what's due"), "Coming up:\n- Quiz 2: COMP 20073, Fri 2026-10-16\n- Essay: ENGL 100, Mon 2026-10-19");
        assert_eq!(reply_of(&f, "ano ang gwa ko"), "Standing mo:\n- MATH 101: 86% so far\n- COMP 20073: 70% so far");
        assert_eq!(reply_of(&f, "what is my gwa"), "Where you stand:\n- MATH 101: 86% so far\n- COMP 20073: 70% so far");
    }

    #[test]
    fn a_grade_question_about_an_unknown_or_ambiguous_subject_shows_all_standings() {
        let f = Facts { subject_names: vec![("MATH 101".into(), "Algebra".into()), ("MATH 102".into(), "Calculus".into())], ..rich() };
        let all = "Where you stand:\n- MATH 101: 86% so far\n- COMP 20073: 70% so far";
        assert_eq!(reply_of(&f, "what is my grade in math"), all, "two MATH subjects: no guessing");
        assert_eq!(reply_of(&f, "what is my grade in history"), all, "no such subject");
        assert_eq!(reply_of(&f, "grade in math 101"), "Where you stand:\n- MATH 101: 86% so far", "named exactly");
    }

    #[test]
    fn data_questions_never_call_the_model_even_with_history_and_a_long_message() {
        let mut m = FakeLlm::new(&[]);
        let hist = vec![("hi".to_string(), "hello".to_string())];
        let long = format!("what is due {}", "please ".repeat(200));
        assert!(answer(&mut m, Template::ChatMl, &rich(), &hist, &long).unwrap().reply.starts_with("Coming up:"));
        assert!(m.prompts.is_empty());
    }

    // C8: the student never reads a code string or a token count.
    #[test]
    fn errors_reach_the_student_in_plain_words_in_both_languages() {
        for (raw, en, tl) in [
            ("IntAssis is busy", "I'm still working on your last message. Give me a second.", "Ginagawa ko pa ang huli mong mensahe. Sandali lang."),
            ("Download the model first", "Turn IntAssis on first, in the You tab.", "I-on muna ang IntAssis sa You tab."),
            ("prompt of 5000 tokens does not fit 4096 context", "That was too long for me. Try a shorter question.", "Masyadong mahaba iyon para sa akin. Subukan ang mas maikling tanong."),
            ("out of memory", "This phone doesn't have enough free memory right now. Close other apps and try again.", "Kulang ang libreng memory ng phone ngayon. Isara ang ibang apps at subukan ulit."),
            ("the reply has no JSON object", "My words got tangled. Ask me again?", "Nagulo ang sagot ko. Pwede mo bang ulitin?"),
            ("the reply is not the expected JSON: expected value at line 1", "My words got tangled. Ask me again?", "Nagulo ang sagot ko. Pwede mo bang ulitin?"),
            ("cancelled", "Something went wrong. Try again.", "May nangyaring mali. Subukan ulit."),
            ("generation cancelled by user", "Something went wrong. Try again.", "May nangyaring mali. Subukan ulit."),
            ("the reply came back empty", "Something went wrong. Try again.", "May nangyaring mali. Subukan ulit."),
            ("no reply queued", "Something went wrong. Try again.", "May nangyaring mali. Subukan ulit."),
            ("", "Something went wrong. Try again.", "May nangyaring mali. Subukan ulit."),
        ] {
            assert_eq!(friendly(raw, false), en, "{raw:?} en");
            assert_eq!(friendly(raw, true), tl, "{raw:?} tl");
            for out in [friendly(raw, false), friendly(raw, true)] {
                assert!(!out.chars().any(|c| c.is_ascii_digit()), "no token counts: {out}");
                assert!(!out.contains("JSON") && !out.contains("token") && !out.contains("context"), "no jargon: {out}");
            }
        }
    }

    #[test]
    fn sentences_written_for_the_student_pass_through_in_either_language() {
        for sentence in [
            "Select the words to explain first.",
            "Type a question first.",
            "The note is empty.",
            "This note is too long for me to take in at once. Select part of it.",
            "This model needs more memory than this phone has free. Try a smaller one.",
            "Is the model loaded?",
            "Do you want to try again?",
        ] {
            assert_eq!(friendly(sentence, false), sentence);
            assert_eq!(friendly(sentence, true), sentence);
        }
    }

    #[test]
    fn raw_errors_never_leak_through_the_catch_all() {
        for raw in ["reqwest: connection reset", "panicked at src/ai.rs:42:7", "llama_decode returned -3", "failed to load /var/mobile/model.gguf"] {
            assert_eq!(friendly(raw, false), "Something went wrong. Try again.", "{raw}");
        }
    }

    // C1, C8: Stop mid-reply. The words were already shown; the raw cut-off JSON is not a note to keep.
    #[test]
    fn stopping_mid_reply_has_streamed_the_words_and_then_errors_in_plain_words() {
        let mut m = Cut(&["{\"reply\": \"Para mag-focus, ", "patayin muna ang phone at", " mag-aral ng 25 min"]);
        let mut seen = String::new();
        let err = answer_streaming(&mut m, Template::Gemma, &facts(), &[], "paano mag-focus?", &mut |w| seen.push_str(w)).unwrap_err();
        assert_eq!(seen, "Para mag-focus, patayin muna ang phone at mag-aral ng 25 min");
        assert_eq!(err, "the reply has no JSON object");
        assert_eq!(friendly(&err, true), "Nagulo ang sagot ko. Pwede mo bang ulitin?");
    }

    #[test]
    fn a_streamed_reply_decodes_escapes_and_matches_the_final_answer() {
        let mut m = FakeLlm::new(&["{\"reply\":\"Sabi ni \\\"Isko\\\":\\nMag-aral ka! caf\\u00e9 \\ud83d\\ude00\"}"]);
        let mut pieces = vec![];
        let a = answer_streaming(&mut m, Template::Gemma, &facts(), &[], "paano mag-aral?", &mut |w| pieces.push(w.to_string())).unwrap();
        assert_eq!(a.reply, "Sabi ni \"Isko\":\nMag-aral ka! café 😀");
        assert_eq!(pieces.concat(), a.reply);
        assert!(pieces.len() > 1, "word by word, not all at once: {pieces:?}");
    }

    #[test]
    fn requests_never_stream_words_to_the_chat() {
        for (msg, raw) in [
            ("add a note: bring calculator", r#"{"text":"bring calculator","subject":"none"}"#),
            ("gawan mo ako ng flashcards sa trees", r#"{"topic":"trees"}"#),
            ("remind me bukas to pay tuition", r#"{"text":"pay tuition"}"#),
        ] {
            let mut seen = String::new();
            let a = answer_streaming(&mut FakeLlm::new(&[raw]), Template::Gemma, &facts(), &[], msg, &mut |w| seen.push_str(w)).unwrap();
            assert!(a.proposal.is_some(), "{msg}");
            assert_eq!(seen, "", "{msg}");
        }
    }

    #[test]
    fn open_replies_are_trimmed_and_thinking_and_fences_are_dropped() {
        let mut m = FakeLlm::new(&["<think>hm</think>\n```json\n{\"reply\":\"  Kaya mo 'yan.  \"}\n```"]);
        assert_eq!(answer(&mut m, Template::Gemma, &facts(), &[], "kaya ko ba?").unwrap().reply, "Kaya mo 'yan.");
    }

    #[test]
    fn model_failures_pass_up_unchanged() {
        assert_eq!(answer(&mut FakeLlm::new(&[]), Template::Gemma, &facts(), &[], "hello"), Err("no reply queued".into()));
        let r = answer(&mut FakeLlm::new(&["I cannot do that"]), Template::Gemma, &facts(), &[], "hello");
        assert_eq!(r, Err("the reply has no JSON object".into()));
        let no_today = Facts { today: None, ..Facts::default() };
        assert_eq!(answer(&mut FakeLlm::new(&[]), Template::Gemma, &no_today, &[], "what is due"), Err("today is unknown".into()));
    }

    #[test]
    fn a_message_is_cut_at_500_chars_before_anything_is_decided() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#]);
        answer(&mut m, Template::Gemma, &facts(), &[], &"a".repeat(600)).unwrap();
        assert!(m.prompts[0].contains(&format!("Student: {}<end_of_turn>", "a".repeat(500))), "exactly 500 chars reach the model");

        // "remind" past the cut is never read, so this is an open question, not a reminder.
        let late = format!("{}remind me", "x ".repeat(300));
        let a = answer(&mut FakeLlm::new(&[r#"{"reply":"hi"}"#]), Template::Gemma, &facts(), &[], &late).unwrap();
        assert_eq!((a.reply.as_str(), a.proposal), ("hi", None));
        let late_grades = format!("{}what are my grades", "x ".repeat(300));
        assert_eq!(answer(&mut FakeLlm::new(&[r#"{"reply":"hi"}"#]), Template::Gemma, &facts(), &[], &late_grades).unwrap().reply, "hi", "not answered from the grades list");

        // Inside the cut it is a reminder, and the rest of the essay is not sent.
        let early = format!("remind me bukas to pay {}", "z".repeat(1000));
        let mut m = FakeLlm::new(&[r#"{"text":"pay"}"#]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], &early).unwrap();
        assert!(matches!(a.proposal, Some(Proposal::SetReminder { .. })));
        let zs = 500 - "remind me bukas to pay ".chars().count();
        assert!(m.prompts[0].contains(&"z".repeat(zs)) && !m.prompts[0].contains(&"z".repeat(zs + 1)));
    }

    #[test]
    fn the_cut_is_in_chars_so_emoji_and_accents_survive() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#]);
        answer(&mut m, Template::Gemma, &facts(), &[], &"😀".repeat(600)).unwrap();
        assert_eq!(m.prompts[0].matches('😀').count(), 500);
        answer(&mut m, Template::Gemma, &facts(), &[], &"é".repeat(499)).unwrap();
        assert_eq!(m.prompts[1].matches('é').count(), 499, "under the limit is untouched");
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "").unwrap();
        assert_eq!(a.reply, "ok", "an empty message is an open question");
        assert!(m.prompts[2].contains("Student: <end_of_turn>"));
    }

    #[test]
    fn only_the_last_four_pairs_of_history_reach_an_open_question() {
        let hist: Vec<(String, String)> = (1..=6).map(|i| (format!("question {i}"), format!("answer {i}"))).collect();
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#]);
        answer(&mut m, Template::Gemma, &facts(), &hist, "and now?").unwrap();
        let p = &m.prompts[0];
        assert!(!p.contains("question 1") && !p.contains("question 2") && !p.contains("answer 2"));
        let at = |s: &str| p.find(s).unwrap_or_else(|| panic!("{s} missing"));
        assert!(at("Student: question 3\nIntAssis: answer 3") < at("Student: question 4\nIntAssis: answer 4"));
        assert!(at("Student: question 5\nIntAssis: answer 5") < at("Student: question 6\nIntAssis: answer 6"), "oldest first");
        assert!(at("## Conversation so far") < at("Student: question 3"));
        assert!(p.ends_with("Student: and now?<end_of_turn>\n<start_of_turn>model\n"));
    }

    #[test]
    fn a_short_history_is_sent_whole_and_no_history_adds_no_section() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#]);
        let hist = vec![("only q".to_string(), "only a".to_string())];
        answer(&mut m, Template::Gemma, &facts(), &hist, "next").unwrap();
        assert!(m.prompts[0].contains("Student: only q\nIntAssis: only a"));
        answer(&mut m, Template::Gemma, &facts(), &[], "next").unwrap();
        assert!(!m.prompts[1].contains("Conversation so far"));
    }

    #[test]
    fn a_request_never_sees_the_conversation_or_the_facts() {
        let hist = vec![("ano ang chain rule".to_string(), "Multiply derivatives".to_string())];
        let f = Facts { hits: vec!["MATH 101: chain rule".into()], ..rich() };
        let mut m = FakeLlm::new(&[r#"{"text":"pay tuition"}"#]);
        answer(&mut m, Template::Gemma, &f, &hist, "remind me bukas to pay tuition").unwrap();
        let p = &m.prompts[0];
        for must_not in ["Conversation so far", "Multiply derivatives", "Quiz 2", "COMP 20073 9:00", "chain rule", "Where you stand", "86%"] {
            assert!(!p.contains(must_not), "{must_not}");
        }
        assert!(p.contains("The student wants a reminder"));
    }

    // C3, C10: a huge note cannot push the schedule out of a 4K window.
    #[test]
    fn the_prompt_budget_holds_and_low_priority_facts_go_first() {
        let f = Facts {
            open_note: Some("n".repeat(20_000)),
            standing: vec!["COMP 20073: 70% so far".into()],
            ..facts()
        };
        let hist = vec![("earlier q".to_string(), "earlier a".to_string())];
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#]);
        answer(&mut m, Template::Gemma, &f, &hist, "ano ang chain rule?").unwrap();
        let p = &m.prompts[0];
        assert!(p.chars().count() <= 7000 + 150, "7000 for the facts plus the question and template: {}", p.chars().count());
        assert!(p.contains("Quiz 2: COMP 20073, Fri 2026-10-16") && p.contains("COMP 20073 9:00"), "today and deadlines survive");
        assert!(p.contains("## Open note") && p.contains("nnnn…"), "the note is cut, not dropped");
        assert!(!p.contains("Conversation so far") && !p.contains("## Grades"), "lower priority goes before the note");
        assert!(p.contains("Student: ano ang chain rule?"), "the question itself always stays");
    }

    #[test]
    fn a_request_without_a_named_day_gets_a_fourteen_day_table() {
        let mut m = FakeLlm::new(&[r#"{"text":"pay","when":"d13"}"#]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "remind me to pay tuition").unwrap();
        let p = &m.prompts[0];
        assert!(p.contains("d0 = Thursday 2026-10-15 (today)") && p.contains("d13 = Wednesday 2026-10-28") && !p.contains("d14"));
        assert_eq!(a.proposal, Some(Proposal::SetReminder { date: Date::new(2026, 10, 28), text: "pay".into() }));
    }

    #[test]
    fn a_named_day_beats_whatever_day_the_model_picks() {
        let mut m = FakeLlm::new(&[r#"{"text":"pay","when":"d5"}"#]);
        let a = answer(&mut m, Template::Gemma, &facts(), &[], "paalala bukas: pay").unwrap();
        assert_eq!(a.proposal, Some(Proposal::SetReminder { date: Date::new(2026, 10, 16), text: "pay".into() }));
    }

    #[test]
    fn a_made_up_day_id_gives_no_reminder_and_asks_to_repeat() {
        for when in ["d14", "d-1", "x5", "5", "", "d", "dd3", "d3.5"] {
            let raw = format!(r#"{{"text":"pay","when":"{when}"}}"#);
            let a = answer(&mut FakeLlm::new(&[&raw]), Template::Gemma, &facts(), &[], "remind me to pay").unwrap();
            assert_eq!(a.proposal, None, "{when:?}");
            assert_eq!(a.reply, "I didn't catch that. Could you say it again?");
        }
        let a = answer(&mut FakeLlm::new(&[r#"{"text":"magbayad","when":"d99"}"#]), Template::Gemma, &facts(), &[], "paalala kailan man").unwrap();
        assert_eq!(a.reply, "Hindi ko nakuha iyon. Pwede mo bang ulitin?");
    }

    #[test]
    fn request_text_is_tidied_before_the_confirm_card() {
        let long = format!("{}.", "w".repeat(200));
        let raw = format!(r#"{{"text":"  {long}  ","subject":"none"}}"#);
        let a = answer(&mut FakeLlm::new(&[&raw]), Template::Gemma, &facts(), &[], "add a note").unwrap();
        assert_eq!(a.proposal, Some(Proposal::AddNote { subject: None, text: "w".repeat(120) }), "cut at 120 chars");
        let a = answer(&mut FakeLlm::new(&[r#"{"text":"Pay tuition. . ","when":"d1"}"#]), Template::Gemma, &facts(), &[], "remind me to pay").unwrap();
        assert_eq!(a.proposal, Some(Proposal::SetReminder { date: Date::new(2026, 10, 16), text: "Pay tuition".into() }), "trailing dots and spaces go");
        assert_eq!(a.reply, "Reminder ready: Pay tuition. Confirm to save it.");
    }

    #[test]
    fn a_request_the_model_leaves_empty_asks_the_student_to_repeat() {
        for (msg, raw, want) in [
            ("add a note", r#"{"text":"","subject":"none"}"#, "I didn't catch that. Could you say it again?"),
            ("add a note", r#"{"text":" . "}"#, "I didn't catch that. Could you say it again?"),
            ("remind me tomorrow", r#"{"text":""}"#, "I didn't catch that. Could you say it again?"),
            ("gawan mo ako ng flashcards", r#"{"topic":""}"#, "Hindi ko nakuha iyon. Pwede mo bang ulitin?"),
            ("make flashcards", r#"{}"#, "I didn't catch that. Could you say it again?"),
        ] {
            let a = answer(&mut FakeLlm::new(&[raw]), Template::Gemma, &facts(), &[], msg).unwrap();
            assert_eq!(a.proposal, None, "{msg} {raw}");
            assert_eq!(a.reply, want, "{msg} {raw}");
        }
    }

    #[test]
    fn an_invented_subject_is_dropped_from_a_note() {
        let a = answer(&mut FakeLlm::new(&[r#"{"text":"read ch 3","subject":"PHYS 999"}"#]), Template::Gemma, &facts(), &[], "add a note: read ch 3").unwrap();
        assert_eq!(a.proposal, Some(Proposal::AddNote { subject: None, text: "read ch 3".into() }));
        assert_eq!(a.reply, "Note ready: read ch 3. Confirm to save it.");
        let a = answer(&mut FakeLlm::new(&[r#"{"text":"magbasa","subject":"comp 20073"}"#]), Template::Gemma, &facts(), &[], "isulat mo: magbasa").unwrap();
        assert_eq!(a.proposal, Some(Proposal::AddNote { subject: None, text: "magbasa".into() }), "the code must match exactly");
    }

    #[test]
    fn the_confirm_card_is_short_and_in_the_students_language() {
        let note = |subject: Option<&str>| Proposal::AddNote { subject: subject.map(Into::into), text: "bring ID".into() };
        assert_eq!(confirm(&note(None), false), "Note ready: bring ID. Confirm to save it.");
        assert_eq!(confirm(&note(Some("MATH 101")), false), "Note ready for MATH 101: bring ID. Confirm to save it.");
        assert_eq!(confirm(&note(None), true), "Handa na ang note: bring ID. I-confirm para i-save.");
        assert_eq!(confirm(&note(Some("MATH 101")), true), "Handa na ang note sa MATH 101: bring ID. I-confirm para i-save.");
        let cards = Proposal::MakeCards { topic: "trees".into() };
        assert_eq!(confirm(&cards, false), "I'll make flashcards on trees. Confirm to start.");
        assert_eq!(confirm(&cards, true), "Gagawa ako ng flashcards sa trees. I-confirm para magsimula.");
        let rem = Proposal::SetReminder { date: THU, text: "pay".into() };
        assert_eq!(confirm(&rem, false), "Reminder ready: pay. Confirm to save it.");
        assert_eq!(confirm(&rem, true), "Handa na ang paalala: pay. I-confirm para i-save.");
    }

    #[test]
    fn the_schema_forces_the_shape_the_rules_chose() {
        let subs = vec!["MATH 101".to_string(), "COMP 20073".to_string()];
        let req = |v: &Value| -> Vec<String> { v["required"].as_array().unwrap().iter().map(|x| x.as_str().unwrap().to_string()).collect() };
        let ask = schema(Intent::Ask, &subs, false);
        assert_eq!(req(&ask), ["reply"]);
        assert_eq!(ask["properties"].as_object().unwrap().len(), 1);

        let note = schema(Intent::Note, &subs, false);
        assert_eq!(note["properties"]["subject"]["enum"], json!(["MATH 101", "COMP 20073", "none"]), "only real subjects, plus none");
        assert!(req(&note).contains(&"text".to_string()) && req(&note).contains(&"subject".to_string()));
        assert!(note["properties"].get("reply").is_none(), "a request has no chatty `reply` field");
        assert_eq!(schema(Intent::Note, &[], false)["properties"]["subject"]["enum"], json!(["none"]));

        let remind = schema(Intent::Remind, &subs, true);
        let ids = remind["properties"]["when"]["enum"].as_array().unwrap();
        assert_eq!((ids.len(), ids[0].as_str(), ids[13].as_str()), (14, Some("d0"), Some("d13")));
        assert!(schema(Intent::Remind, &subs, false)["properties"].get("when").is_none(), "no day to pick when the message named one");

        assert_eq!(req(&schema(Intent::Cards, &subs, false)), ["topic"]);
    }

    #[test]
    fn the_template_decides_how_the_prompt_is_wrapped() {
        let mut m = FakeLlm::new(&[r#"{"reply":"a"}"#, r#"{"reply":"b"}"#]);
        answer(&mut m, Template::ChatMl, &facts(), &[], "hello").unwrap();
        answer(&mut m, Template::Gemma, &facts(), &[], "hello").unwrap();
        assert!(m.prompts[0].starts_with("<|im_start|>system\nYou are IntAssis"));
        assert!(m.prompts[1].starts_with("<start_of_turn>user\nYou are IntAssis"));
    }

    #[test]
    fn the_subject_section_appears_only_when_one_subject_is_named() {
        // The subject section only appears when the message names exactly one subject.
        let mut m = FakeLlm::new(&[r#"{"reply":"a"}"#, r#"{"reply":"b"}"#]);
        answer(&mut m, Template::Gemma, &rich(), &[], "paano mag-aral ng data structures?").unwrap();
        assert!(m.prompts[0].contains("The student is asking about\nCOMP 20073 Data Structures"));
        answer(&mut m, Template::Gemma, &rich(), &[], "paano mag-aral?").unwrap();
        assert!(!m.prompts[1].contains("The student is asking about"));
        assert!(!m.prompts[1].contains("pick one id"), "open questions never pick dates");
    }
}
