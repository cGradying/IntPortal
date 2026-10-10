//! IntAssis on a real model: does the action fire, is the date right, is the
//! guide sane? `cargo run --release -p intportal-llm --example assis -- <gemma.gguf>`
use intportal_ai::{assis::{answer, Facts}, outline, prompt::Template, why::explain};
use intportal_core::today::Date;
use intportal_llm::{Device, Llama};

fn main() {
    let path = std::env::args().nth(1).expect("chat model.gguf");
    let tpl = if path.contains("gemma") { Template::Gemma } else { Template::ChatMl };
    let mut m = Llama::load(path.as_ref(), 4096, Device::Gpu).unwrap();
    let today = Date::new(2026, 10, 15); // a Thursday
    let facts = Facts {
        today: Some(today),
        classes_today: vec!["COMP 20073 Data Structures, 9:00-10:30, Rm 301".into(), "MATH 101 Calculus, 13:00-14:30".into()],
        due: vec!["Quiz 2: COMP 20073, Fri 2026-10-16".into(), "Midterm exam: MATH 101, Wed 2026-10-21".into()],
        standing: vec!["MATH 101: 82% so far, needs 76% on the rest to reach 1.75".into()],
        subjects: vec!["COMP 20073".into(), "MATH 101".into()],
        ..Facts::default()
    };
    for q in [
        "Ano ang due ko this week?",
        "Anong klase ko ngayon?",
        "Pwede mo ba akong i-remind bukas about Math 101 assignment?",
        "Mag-remind ka sa akin na bayaran ang tuition sa Lunes.",
        "Pa-add naman ng note sa COMP 20073: bring calculator sa Friday quiz.",
        "Gawan mo ako ng flashcards sa binary trees",
        "Okay lang ba ako sa Math?",
    ] {
        match answer(&mut m, tpl, &facts, &[], q) {
            Ok(a) => println!("Q: {q}\n   {}\n   -> {:?}\n", a.reply, a.proposal),
            Err(e) => println!("Q: {q}\n   ERROR {e}\n"),
        }
    }
    println!("{:?}\n", explain(&mut m, tpl, "Root of a min-heap?", "The smallest item", "the largest item", Some("Heaps: parent is <= its children, so the root is the minimum.")));
    println!("{:#?}", outline::from_title(&mut m, tpl, "COMP 20073 Data Structures and Algorithms", 6, &mut |w, n| { eprintln!("week {w}/{n}"); true }).map(|v| v.iter().map(|i| format!("wk{} {:?} {}", i.week.unwrap(), i.kind, i.topic)).collect::<Vec<_>>()));
}
