//! Notes-from-chat probe (spec 062 C1–C6): ten fixed chats turned into notes by a real model, printed with the
//! time, the bullets kept and the bullets the number check dropped.
//! Then ten edits on fixed notes (C9–C11): an edit passes when the note has what was asked and keeps every
//! line it was not asked to touch.
//! `cargo run --release -p intportal-llm --example notes -- <chat.gguf> [cpu]`
use intportal_ai::{chatnote, edit, llm::Llm, prompt::Template};
use intportal_llm::{Device, Llama};

/// Counts the bullets the model wrote, so the probe can show how many the check dropped.
struct Count<'a>(&'a mut Llama, usize);

impl Llm for Count<'_> {
    fn generate(&mut self, p: &str, s: Option<&serde_json::Value>, n: u32, f: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        let out = self.0.generate(p, s, n, f)?;
        self.1 = serde_json::from_str::<serde_json::Value>(&out).ok().and_then(|v| v["bullets"].as_array().map(Vec::len)).unwrap_or(0);
        Ok(out)
    }
    fn embed(&mut self, t: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        self.0.embed(t)
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let dev = if a.iter().any(|x| x == "cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(std::path::Path::new(a.get(1).expect("chat.gguf")), 4096, dev).expect("load");
    let subjects = vec!["COMP 20073".to_string(), "MATH 101".to_string(), "HIST 1013".to_string()];
    let p = |me: &str, lar: &str| (me.to_string(), lar.to_string());
    let chats: Vec<Vec<(String, String)>> = vec![
        vec![p("what is a heap?", "A heap is a complete binary tree where each parent is at least as big as its children (a max-heap). Insert and remove-max take O(log n); reading the max is O(1).")],
        vec![p("explain big O", "Big O describes how the running time grows with input size n. O(1) is constant, O(n) grows in step with n, and O(n^2) grows with its square, like two nested loops."), p("and O(log n)?", "O(log n) grows very slowly: each step halves the work, as in binary search on a sorted list.")],
        vec![p("power rule?", "The power rule: the derivative of x^n is n times x^(n-1). So x^3 becomes 3x^2.")],
        vec![p("chain rule", "The chain rule: the derivative of f(g(x)) is f'(g(x)) times g'(x). For (2x+1)^3 that is 3(2x+1)^2 times 2.")],
        vec![p("who started the Katipunan?", "Andres Bonifacio founded the Katipunan in 1892 with Deodato Arellano and others, to fight Spanish rule."), p("when did the revolution start?", "The Philippine Revolution began in August 1896, after the Katipunan was discovered.")],
        vec![p("what is recursion", "Recursion is when a function calls itself on a smaller part of the problem. It needs a base case that stops the calls, or it runs forever."), p("example?", "Factorial: factorial(n) is n times factorial(n-1), and factorial(0) is 1.")],
        vec![p("when is my quiz in COMP 20073?", "Quiz 2: COMP 20073, Fri 2026-10-16."), p("what does it cover", "From your notes: stacks, queues and linked lists, chapters 3 to 5.")],
        vec![p("hi", "Hi! What are we studying today?"), p("osmosis", "Osmosis is water moving through a membrane toward the side with more dissolved substance. It needs no energy from the cell.")],
        vec![p("difference between stack and queue", "A stack is last in, first out: push and pop at the top. A queue is first in, first out: enqueue at the back, dequeue at the front.")],
        vec![p("how do I study for finals", "Start a week early. Make flashcards of the terms, do the past quizzes again, and review your misses each day. Sleep well the night before.")],
    ];
    let (mut made, mut kept, mut wrote) = (0, 0, 0);
    for (n, chat) in chats.iter().enumerate() {
        let t = std::time::Instant::now();
        let mut c = Count(&mut m, 0);
        let note = chatnote::make(&mut c, Template::ChatMl, chat, &subjects);
        let dt = t.elapsed().as_secs_f64();
        wrote += c.1;
        match note {
            Ok(Some(note)) => {
                made += 1;
                let k = note.text.lines().count();
                kept += k;
                println!("== {} in {dt:.1}s: {} [{}] {k} of {} bullets kept", n + 1, note.title, note.subject.unwrap_or_default(), c.1);
                println!("{}", note.text);
            }
            other => println!("== {} in {dt:.1}s: no note ({other:?})", n + 1),
        }
    }
    println!("\n{made} of {} chats made a note; {kept} of {wrote} bullets kept", chats.len());

    let note = |t: &str| edit::NoteRef { key: "note:1".into(), name: "Quiz".into(), subject: None, text: t.into() };
    let quiz = "Quiz 2 on Friday, Oct 16\nCovers stacks and queues\nBring a calculator\nRoom 302";
    let heap = "- A heap is a compelte binary tree\n- Max-heap: parent >= children\n- Insert is O(log n)";
    let chat = vec![p("power rule?", "The derivative of x^n is n times x^(n-1).")];
    use edit::Kind::*;
    // (note, kind, request, must contain, must still contain)
    let cases: Vec<(&str, edit::Kind, &str, &str, Vec<&str>)> = vec![
        (quiz, Change, "change the quiz day to Monday", "Monday", vec!["Covers stacks and queues", "Bring a calculator", "Room 302"]),
        (quiz, Change, "the room is now 305", "305", vec!["Covers stacks and queues", "Bring a calculator"]),
        (quiz, Change, "remove the calculator line", "Room 302", vec!["Covers stacks and queues", "Quiz 2 on Friday, Oct 16"]),
        (quiz, Change, "it also covers linked lists", "linked lists", vec!["Bring a calculator", "Room 302"]),
        (heap, Change, "change insert to O(log n) worst case", "worst case", vec!["- A heap is a compelte binary tree", "- Max-heap: parent >= children"]),
        (heap, Append, "add that reading the max is O(1)", "O(1)", vec!["- Insert is O(log n)"]),
        (quiz, Append, "add: bring my ID too", "ID", vec!["Room 302"]),
        ("Derivatives\n- Chain rule: f'(g(x)) g'(x)", Append, "add the power rule you just told me", "x^(n-1)", vec!["- Chain rule: f'(g(x)) g'(x)"]),
        ("quiz frday covers stcks n queues\nbring calc", Tidy, "fix the spelling", "riday", vec![]),
        (heap, Change, "fix the typo in the first line", "complete binary tree", vec!["- Insert is O(log n)"]),
    ];
    // What a change must have taken out.
    let gone = |msg: &str| match msg { "remove the calculator line" => Some("calculator"), "change the quiz day to Monday" => Some("Friday"), "the room is now 305" => Some("302"), "fix the typo in the first line" => Some("compelte"), _ => None };
    let mut pass = 0;
    for (k, (text, kind, msg, want, keep)) in cases.iter().enumerate() {
        let t = std::time::Instant::now();
        let out = edit::rewrite(&mut m, Template::ChatMl, *kind, &note(text), &chat, msg);
        let dt = t.elapsed().as_secs_f64();
        let ok = out.as_ref().is_ok_and(|o| o.contains(want) && keep.iter().all(|l| o.contains(l)) && !gone(msg).is_some_and(|g| o.contains(g)));
        pass += usize::from(ok);
        println!("== edit {} {} in {dt:.1}s: {msg}\n{}", k + 1, if ok { "PASS" } else { "FAIL" }, out.unwrap_or_else(|e| format!("Err: {e}")));
    }
    println!("\n{pass} of {} edits applied as asked", cases.len());
}
