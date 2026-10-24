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

    #[test]
    fn same_priority_sections_keep_their_given_order_and_the_first_gets_the_room() {
        let a = "a".repeat(30);
        let b = "b".repeat(30);
        // "S" + 2 * (7-char head + 30) = 75 would fit both; 50 fits only the first whole.
        let p = build("S", &[s("A", &a, 5), s("B", &b, 5)], 50);
        assert!(p.contains(&a) && !p.contains(&b));
        assert!(p.chars().count() <= 50);
    }

    #[test]
    fn a_later_high_priority_section_is_kept_but_printed_in_its_place() {
        let long = "z".repeat(300);
        let p = build("S", &[s("first", &long, 1), s("second", "keep", 9)], 60);
        assert_eq!(p, "S\n\n## second\nkeep");
    }

    #[test]
    fn the_cut_needs_room_for_forty_chars_of_body() {
        // head "\n\n## A\n" is 7 chars; "S" is 1
        let long = "x".repeat(200);
        assert_eq!(build("S", &[s("A", &long, 1)], 47), "S", "46 left: 39 chars of body is not useful");
        let p = build("S", &[s("A", &long, 1)], 48);
        assert_eq!(p.chars().count(), 48);
        assert!(p.ends_with(&format!("{}…", "x".repeat(39))));
    }

    #[test]
    fn the_system_text_always_stays_even_over_budget() {
        let sys = "s".repeat(100);
        assert_eq!(build(&sys, &[s("A", "body", 9)], 10), sys);
        assert_eq!(build(&sys, &[], 0), sys);
        assert_eq!(build("", &[], 10), "");
    }

    #[test]
    fn a_section_that_fits_exactly_is_not_cut() {
        let p = build("S", &[s("A", "12345", 1)], 1 + 7 + 5);
        assert_eq!(p, "S\n\n## A\n12345");
    }

    #[test]
    fn budget_counts_chars_not_bytes() {
        let long = "ñ".repeat(500);
        let p = build("Sí", &[s("nota", &long, 5)], 100);
        assert_eq!(p.chars().count(), 100);
        assert!(p.ends_with('…'));
        let emoji = build("S", &[s("E", &"😀".repeat(100), 1)], 60);
        assert_eq!(emoji.chars().count(), 60, "no panic or cut inside a char");
    }

    #[test]
    fn a_smaller_section_still_fits_after_a_bigger_one_is_dropped_whole() {
        // Priority 9 is cut; once nothing is left the rest are dropped, not squeezed in.
        let big = "b".repeat(500);
        let p = build("S", &[s("big", &big, 9), s("small", "tiny", 1)], 80);
        assert!(p.contains("big") && !p.contains("small"));
    }

    #[test]
    fn templates_wrap_the_same_text_as_their_helpers() {
        assert_eq!(Template::ChatMl.wrap("S", "U"), chatml("S", "U"));
        assert_eq!(Template::Gemma.wrap("S", "U"), gemma("S", "U"));
        assert_eq!(gemma("S", "U"), "<start_of_turn>user\nS\n\nU<end_of_turn>\n<start_of_turn>model\n");
        assert!(!Template::Gemma.wrap("S", "U").contains("system"), "Gemma has no system role");
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

/// Gemma has no system role: the system text leads the user turn.
pub fn gemma(system: &str, user: &str) -> String {
    format!("<start_of_turn>user\n{system}\n\n{user}<end_of_turn>\n<start_of_turn>model\n")
}

/// LFM2 / LFM2.5 Instruct: the same turns as ChatML, with no think block (the
/// GGUF template is `bos + <|im_start|>role\n...<|im_end|>\n`, then
/// `<|im_start|>assistant\n`). The BOS comes from the tokenizer (`add_bos_token`).
pub fn lfm2(system: &str, user: &str) -> String {
    format!("<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n")
}

#[cfg(test)]
mod lfm2_tests {
    #[test]
    fn no_think_block() {
        assert_eq!(super::lfm2("S", "U"), "<|im_start|>system\nS<|im_end|>\n<|im_start|>user\nU<|im_end|>\n<|im_start|>assistant\n");
    }
}

/// How a model wants its prompt wrapped.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Template {
    ChatMl,
    Gemma,
    Lfm2,
}

impl Template {
    pub fn wrap(self, system: &str, user: &str) -> String {
        match self {
            Template::ChatMl => chatml(system, user),
            Template::Gemma => gemma(system, user),
            Template::Lfm2 => lfm2(system, user),
        }
    }
}
