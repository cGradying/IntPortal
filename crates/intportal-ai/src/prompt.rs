/// One block of context. Higher `priority` survives a tight budget.
pub struct Section<'a> {
    pub title: &'a str,
    pub body: &'a str,
    pub priority: u8,
}

const MIN_USEFUL: usize = 40;

/// Joins `system` and the sections into one prompt of at most `budget` chars.
/// The system text always stays. Sections are admitted by priority; the one
/// that overflows is cut with "…" if at least `MIN_USEFUL` chars fit, else
/// dropped. Kept sections stay in their given order.
pub fn build(system: &str, sections: &[Section], budget: usize) -> String {
    let mut left = budget.saturating_sub(system.chars().count());
    let mut order: Vec<usize> = (0..sections.len()).collect();
    order.sort_by_key(|&i| std::cmp::Reverse(sections[i].priority)); // stable: ties keep given order
    let mut kept: Vec<Option<String>> = vec![None; sections.len()];
    for i in order {
        let s = &sections[i];
        let head = format!("\n\n## {}\n", s.title);
        let cost = head.chars().count() + s.body.chars().count();
        let block = if cost <= left {
            format!("{head}{}", s.body)
        } else if left >= head.chars().count() + MIN_USEFUL {
            let room = left - head.chars().count() - 1;
            format!("{head}{}…", s.body.chars().take(room).collect::<String>())
        } else {
            continue;
        };
        left -= block.chars().count();
        kept[i] = Some(block);
    }
    let mut out = system.to_string();
    out.extend(kept.into_iter().flatten());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s<'a>(title: &'a str, body: &'a str, priority: u8) -> Section<'a> {
        Section { title, body, priority }
    }

    #[test]
    fn fits_everything_in_order() {
        let p = build("SYS", &[s("A", "aa", 1), s("B", "bb", 9)], 1000);
        assert_eq!(p, "SYS\n\n## A\naa\n\n## B\nbb");
    }

    #[test]
    fn low_priority_goes_first_and_budget_holds() {
        let long = "x".repeat(200);
        let p = build("SYS", &[s("low", &long, 1), s("high", "keep me", 9)], 60);
        assert!(p.contains("keep me"));
        assert!(!p.contains("low"));
        assert!(p.chars().count() <= 60);
    }

    #[test]
    fn overflowing_section_is_cut_with_ellipsis() {
        let long = "y".repeat(500);
        let p = build("SYS", &[s("note", &long, 5)], 120);
        assert!(p.ends_with('…'));
        assert_eq!(p.chars().count(), 120);
    }
}

/// Wraps a system and a user message in ChatML (Qwen, and most small models).
/// The empty think block turns Qwen3's thinking off, which a phone can't afford.
pub fn chatml(system: &str, user: &str) -> String {
    format!(
        "<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    )
}

#[cfg(test)]
mod chatml_tests {
    #[test]
    fn ends_open_for_the_assistant() {
        let p = super::chatml("S", "U");
        assert!(p.starts_with("<|im_start|>system\nS<|im_end|>"));
        assert!(p.ends_with("<|im_start|>assistant\n<think>\n\n</think>\n\n"));
    }
}
