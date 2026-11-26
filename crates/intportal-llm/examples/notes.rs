//! Notes-from-chat probe (spec 062 C1–C6): ten fixed chats turned into notes by a real model, printed with the
//! time, the bullets kept and the bullets the number check dropped.
//! `cargo run --release -p intportal-llm --example notes -- <chat.gguf> [cpu]`
use intportal_ai::{chatnote, llm::Llm, prompt::Template};
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
}
