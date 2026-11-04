//! A whole chat through the public API, the way `ai_ask` drives it: each
//! open question's exchange feeds the next one; requests and exact answers do not.
use intportal_ai::{
    assis::{answer, answer_streaming, friendly, Facts, Proposal, Route},
    llm::FakeLlm,
    prompt::Template,
};
use intportal_core::today::Date;

const THU: Date = Date { y: 2026, m: 10, d: 15 };

fn facts() -> Facts {
    Facts {
        today: Some(THU),
        classes_today: vec!["COMP 20073 9:00".into()],
        due: vec!["Quiz 2: COMP 20073, Fri 2026-10-16".into()],
        standing: vec!["MATH 101: 86% so far".into()],
        subjects: vec!["COMP 20073".into(), "MATH 101".into()],
        subject_names: vec![("MATH 101".into(), "Mathematics".into()), ("COMP 20073".into(), "Data Structures".into())],
        // the search found a note, so an open question is in scope and reaches the model
        hits: vec!["MATH 101 · Mathematics: the chain rule multiplies derivatives; focus on one problem at a time".into()],
        ..Facts::default()
    }
}

#[test]
fn only_open_questions_become_history_for_the_next_turn() {
    let mut llm = FakeLlm::new(&[r#"{"reply":"Multiply the derivatives."}"#, r#"{"text":"pay tuition"}"#, r#"{"reply":"Gaya ng sinabi ko: multiply."}"#]);
    let mut history: Vec<(String, String)> = vec![];
    let chat = |llm: &mut FakeLlm, history: &mut Vec<(String, String)>, msg: &str| {
        let a = answer(llm, Template::Gemma, &facts(), history, msg).unwrap();
        // ai.rs keeps a turn as "ask" only when the model itself answered an open question.
        if a.route == Route::Model {
            history.push((msg.to_string(), a.reply.clone()));
        }
        a
    };

    chat(&mut llm, &mut history, "ano ang chain rule?");
    let due = chat(&mut llm, &mut history, "what is due?");
    assert!(due.reply.contains("\n- Quiz 2: COMP 20073, Fri 2026-10-16"), "the fact is in the voiced answer: {}", due.reply);
    let rem = chat(&mut llm, &mut history, "remind me bukas to pay tuition");
    assert!(matches!(rem.proposal, Some(Proposal::SetReminder { .. })));
    chat(&mut llm, &mut history, "paano ulit?");

    assert_eq!(llm.prompts.len(), 3, "the exact answer skipped the model");
    let last = &llm.prompts[2];
    assert!(last.contains("Student: ano ang chain rule?\nLAR: Multiply the derivatives."));
    let memory = &last[last.find("## Conversation so far").expect("a memory section")..];
    assert!(!memory.contains("what is due") && !memory.contains("pay tuition"), "no exact answers or requests in the memory");
}

#[test]
fn a_whole_taglish_session_stays_plain_and_never_leaks_errors() {
    let mut llm = FakeLlm::new(&["not json at all"]);
    let mut seen = String::new();
    let err = answer_streaming(&mut llm, Template::ChatMl, &facts(), &[], "paano mag-focus?", &mut |w| seen.push_str(w)).unwrap_err();
    let shown = friendly(&err, true);
    assert_eq!(shown, "Nagulo ang sagot ko. Pwede mo bang ulitin?");
    assert!(!shown.contains("JSON"));
    assert_eq!(seen, "", "nothing was streamed from a reply that never started");

    let a = answer(&mut FakeLlm::new(&[]), Template::ChatMl, &facts(), &[], "bagsak ba ako sa math?").unwrap();
    assert!(a.reply.ends_with("- MATH 101: 86% so far") || a.reply.contains("\n- MATH 101: 86% so far\n"), "{}", a.reply);
}

// C3: the notes LAR was shown are in the prompt for an open question, so the chip can name them.
#[test]
fn search_hits_reach_the_model_only_for_open_questions() {
    let f = facts();
    let mut llm = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"topic":"chain rule"}"#]);
    answer(&mut llm, Template::Gemma, &f, &[], "paano gamitin ang chain rule?").unwrap();
    answer(&mut llm, Template::Gemma, &f, &[], "gawan mo ako ng flashcards sa chain rule").unwrap();
    assert!(llm.prompts[0].contains("## From the student's notes\n- MATH 101 · Mathematics: the chain rule"));
    assert!(!llm.prompts[1].contains("From the student's notes"));
}
