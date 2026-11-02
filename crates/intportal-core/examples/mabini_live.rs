//! Live check of the eMabini client against your own account:
//! `cargo run --example mabini_live`. Prints counts only, never the password
//! or any course name.

use intportal_core::mabini::LoginPage;
use std::io::Write;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    print!("Student number: ");
    std::io::stdout().flush().unwrap();
    let mut n = String::new();
    std::io::stdin().read_line(&mut n).unwrap();
    let password = rpassword::prompt_password("Password (hidden): ").unwrap();
    let signed_in = match LoginPage::fetch().await {
        Ok(page) => page.sign_in(n.trim(), &password).await,
        Err(e) => Err(e),
    };
    let client = match signed_in {
        Ok(c) => c,
        Err(e) => return println!("sign-in failed: {e}"),
    };
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64;
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
