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
    }
}
