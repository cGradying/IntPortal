//! Live check of the eMabini client against your own account:
//! `cargo run --example mabini_live`. Prints counts only, never the password
//! or any course name.

use intportal_core::mabini::LoginPage;
use intportal_core::portal::MABINI;
use intportal_core::sis::{post_once, Ledger};
use std::io::Write;

/// The same 3-per-15-minutes count the app keeps, in a file beside this run.
const LEDGER: &str = "target/mabini-live-guard.json";

#[tokio::main(flavor = "current_thread")]
async fn main() {
    print!("Student number: ");
    std::io::stdout().flush().unwrap();
    let mut n = String::new();
    std::io::stdin().read_line(&mut n).unwrap();
    let password = rpassword::prompt_password("Password (hidden): ").unwrap();
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64;
    let mut ledger = Ledger::load(std::fs::read_to_string(LEDGER).ok().as_deref(), now as u64, &MABINI);
    let save = |l: &Ledger| std::fs::write(LEDGER, serde_json::to_string(l).unwrap()).map_err(|e| e.to_string());
    let signed_in = post_once(&mut ledger, now as u64, false, save, LoginPage::fetch(), |page| async move { page.sign_in(n.trim(), &password).await }).await;
    let client = match signed_in {
        Ok(c) => c,
        Err(e) => return println!("sign-in failed: {e}"),
    };
    match client.courses().await {
        Ok(c) => println!("courses: {}, with a split name: {}", c.len(), c.iter().filter(|c| !c.term.is_empty()).count()),
        Err(e) => println!("courses failed: {e}"),
    }
    match client.deadlines(now - 86_400, 20).await {
        Ok(d) => println!("deadlines: {}, overdue: {}", d.len(), d.iter().filter(|d| d.overdue).count()),
        Err(e) => println!("deadlines failed: {e}"),
    }
    match client.grades().await {
        Ok(g) => println!("grade rows: {}, graded: {}", g.len(), g.iter().filter(|g| g.grade.is_some()).count()),
        Err(e) => println!("grades failed: {e}"),
    }
}
