//! Live check of the real core against your own SIS account:
//! `cargo run --example live`. Prints counts and your GPA, never the password.

use intportal_core::sis::{sign_in_guarded, Credentials, Ledger, SisClient};
use intportal_core::{grades, schedule};
use std::io::Write;

fn ask(label: &str) -> String {
    print!("{label}: ");
    std::io::stdout().flush().unwrap();
    let mut s = String::new();
    std::io::stdin().read_line(&mut s).unwrap();
    s.trim().to_string()
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let c = Credentials {
        student_number: ask("Student number"),
        birth_month: ask("Birth month (number)").parse().expect("month"),
        birth_day: ask("Birth day").parse().expect("day"),
        birth_year: ask("Birth year").parse().expect("year"),
        password: rpassword::prompt_password("Password (hidden): ").unwrap(),
    };
    // A throwaway ledger: this example doesn't share the app's count.
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
    let (client, rows) = match sign_in_guarded(SisClient::new, &c, None, &mut Ledger::default(), now, false).await {
        Ok(ok) => ok,
        Err(e) => return println!("sign-in failed: {e}"),
    };
    let sessions = schedule::parse(&rows);
    let unparsed = rows.iter().filter(|r| schedule::parse_row(r).is_empty()).count();
    println!("host {}: {} schedule rows, {} sessions, {} rows with no parseable time", client.host(), rows.len(), sessions.len(), unparsed);
    match client.grades().await {
        Ok((g, summary)) => {
            let subjects = grades::parse(&g);
            let posted = subjects.iter().filter(|s| s.is_posted()).count();
            println!("grades: {} subjects, {} posted, computed GPA {:?}, summary keys {:?}", subjects.len(), posted, grades::gpa(&subjects), summary.keys().collect::<Vec<_>>());
        }
        Err(e) => println!("grades failed: {e}"),
    }
    match client.grade_history().await {
        Ok(h) => println!("past terms with posted grades: {:?}", h.iter().map(|r| (r.school_year.clone().unwrap_or_default(), r.semester.clone().unwrap_or_default(), r.gpa())).collect::<Vec<_>>()),
        Err(e) => println!("history failed: {e}"),
    }
}
