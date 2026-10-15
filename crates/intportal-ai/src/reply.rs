use serde::de::DeserializeOwned;

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum ReplyError {
    #[error("the reply has no JSON object")]
    NoJson,
    #[error("the reply is not the expected JSON: {0}")]
    Malformed(String),
}

/// Drops `<think>…</think>` blocks. An unclosed block (the model was cut off
/// mid-thought) drops everything after it.
pub fn strip_think(raw: &str) -> String {
    let mut out = String::new();
    let mut rest = raw;
    while let Some(i) = rest.find("<think>") {
        out.push_str(&rest[..i]);
        match rest[i..].find("</think>") {
            Some(j) => rest = &rest[i + j + "</think>".len()..],
            None => return out.trim().to_string(),
        }
    }
    out.push_str(rest);
    out.trim().to_string()
}

/// Strips thinking, then parses the outermost `{…}` so code fences or a
/// sentence around the JSON don't matter.
pub fn parse<T: DeserializeOwned>(raw: &str) -> Result<T, ReplyError> {
    let text = strip_think(raw);
    let (a, b) = (text.find('{'), text.rfind('}'));
    let json = match (a, b) {
        (Some(a), Some(b)) if a < b => &text[a..=b],
        _ => return Err(ReplyError::NoJson),
    };
    serde_json::from_str(json).map_err(|e| ReplyError::Malformed(e.to_string()))
}

fn hex4(chars: &mut std::str::Chars) -> Option<u32> {
    let hex: String = chars.by_ref().take(4).collect();
    if hex.len() == 4 { u32::from_str_radix(&hex, 16).ok() } else { None }
}

/// The text of the `"reply"` string so far in a JSON object that is still
/// being written, with escapes decoded. None until the string has started.
fn partial_reply(raw: &str) -> Option<String> {
    let after_key = &raw[raw.find("\"reply\"")? + "\"reply\"".len()..];
    let body = after_key.trim_start().strip_prefix(':')?.trim_start().strip_prefix('"')?;
    let (mut out, mut chars) = (String::new(), body.chars());
    while let Some(c) = chars.next() {
        match c {
            '"' => break,
            '\\' => match chars.next() {
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('u') => {
                    let Some(mut cp) = hex4(&mut chars) else { break }; // cut mid-escape
                    if (0xD800..0xDC00).contains(&cp) {
                        // First half of a pair: show nothing until the second half is here too.
                        let mut ahead = chars.clone();
                        let low = (ahead.next() == Some('\\') && ahead.next() == Some('u')).then(|| hex4(&mut ahead)).flatten();
                        let Some(low) = low.filter(|l| (0xDC00..0xE000).contains(l)) else { break };
                        (chars, cp) = (ahead, 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00));
                    }
                    match char::from_u32(cp) {
                        Some(ch) => out.push(ch),
                        None => break,
                    }
                }
                Some('r') => out.push('\r'),
                Some('b') => out.push('\u{8}'),
                Some('f') => out.push('\u{c}'),
                Some(other) => out.push(other),
                None => break,
            },
            c => out.push(c),
        }
    }
    Some(out)
}

/// Turns the model's raw JSON, fed piece by piece, into the growing reply text,
/// so the chat can show words as they come.
#[derive(Default)]
pub struct ReplyStream {
    raw: String,
    sent: usize,
}

impl ReplyStream {
    /// The new part of the reply since the last call, if any.
    pub fn feed(&mut self, piece: &str) -> Option<String> {
        self.raw.push_str(piece);
        let text = partial_reply(&self.raw)?;
        let new = text.get(self.sent..)?;
        self.sent = text.len();
        (!new.is_empty()).then(|| new.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize, Debug, PartialEq)]
    struct R {
        reply: String,
    }

    #[test]
    fn strips_think_blocks() {
        assert_eq!(strip_think("<think>hmm</think>\nHi <think>x</think>there"), "Hi there");
        assert_eq!(strip_think("Hi <think>cut off"), "Hi");
    }

    #[test]
    fn parses_through_think_and_fences() {
        let raw = "<think>{\"reply\":\"no\"}</think>\n```json\n{\"reply\":\"yes\"}\n```";
        assert_eq!(parse::<R>(raw), Ok(R { reply: "yes".into() }));
    }

    #[test]
    fn reports_malformed_and_missing_json() {
        assert!(matches!(parse::<R>("{\"reply\": "), Err(ReplyError::NoJson)));
        assert!(matches!(parse::<R>("{\"reply\": 3}"), Err(ReplyError::Malformed(_))));
        assert_eq!(parse::<R>("just words"), Err(ReplyError::NoJson));
    }

    #[test]
    fn a_stream_yields_the_reply_text_as_it_grows() {
        let mut s = ReplyStream::default();
        let pieces = ["{\"re", "ply\": \"Hel", "lo, \\\"", "you\\n", "ok\"}"];
        let got: Vec<_> = pieces.iter().filter_map(|p| s.feed(p)).collect();
        assert_eq!(got.concat(), "Hello, \"you\nok");
        assert_eq!(got.first().map(String::as_str), Some("Hel"), "nothing before the string starts");
    }

    #[test]
    fn a_stream_waits_out_half_an_escape_and_ignores_other_keys() {
        let mut s = ReplyStream::default();
        assert_eq!(s.feed("{\"reply\":\"a\\u00"), Some("a".into()));
        assert_eq!(s.feed("e9b\"}"), Some("éb".into()));
        let mut t = ReplyStream::default();
        assert_eq!(t.feed("{\"text\":\"x\"}"), None);
    }

    /// Feeds `raw` in pieces of `n` chars and returns what the chat would show.
    fn streamed(raw: &str, n: usize) -> String {
        let chars: Vec<char> = raw.chars().collect();
        let mut s = ReplyStream::default();
        chars.chunks(n).filter_map(|c| s.feed(&c.iter().collect::<String>())).collect()
    }

    // C1: words appear as they are written, wherever the model's pieces split.
    #[test]
    fn escapes_split_at_any_point_still_decode() {
        let raw = r#"{"reply":"Line1\nLine2 \"quoted\" \\ back \u00e9 \t tab ñ 日本"}"#;
        let want = "Line1\nLine2 \"quoted\" \\ back é \t tab ñ 日本";
        for n in 1..=raw.chars().count() {
            assert_eq!(streamed(raw, n), want, "pieces of {n} chars");
        }
    }

    #[test]
    fn a_stream_never_repeats_or_loses_words() {
        let raw = r#"{"reply":"May quiz ka bukas.\nMag-aral ka na!"}"#;
        let mut s = ReplyStream::default();
        let mut shown = String::new();
        for c in raw.chars() {
            if let Some(w) = s.feed(&c.to_string()) {
                assert!(!w.is_empty());
                shown.push_str(&w);
                assert!("May quiz ka bukas.\nMag-aral ka na!".starts_with(&shown), "only grows: {shown:?}");
            }
        }
        assert_eq!(shown, "May quiz ka bukas.\nMag-aral ka na!");
    }

    #[test]
    fn nothing_is_shown_until_the_reply_string_starts() {
        let mut s = ReplyStream::default();
        assert_eq!(s.feed(""), None);
        assert_eq!(s.feed("{\"rep"), None);
        assert_eq!(s.feed("ly\""), None, "key without value yet");
        assert_eq!(s.feed(" :"), None);
        assert_eq!(s.feed(" \""), None, "opening quote shows nothing yet");
        assert_eq!(s.feed("Hi"), Some("Hi".into()));
        assert_eq!(s.feed(""), None);
    }

    #[test]
    fn text_after_the_closing_quote_and_other_keys_are_not_shown() {
        let mut s = ReplyStream::default();
        assert_eq!(s.feed(r#"{"reply":"done","text":"later"#), Some("done".into()));
        assert_eq!(s.feed(r#" more"}"#), None);
        assert_eq!(streamed(r#"{"text":"first","reply":"second","topic":"third"}"#, 5), "second", "key order does not matter");
        assert_eq!(streamed(r#"{"reply" :   "spaced"}"#, 3), "spaced");
        assert_eq!(streamed(r#"{"reply": 3, "text": "x"}"#, 4), "", "a non-string reply shows nothing");
        assert_eq!(streamed(r#"{"text":"mentions reply but has none"}"#, 4), "");
    }

    #[test]
    fn a_surrogate_pair_arrives_as_one_emoji() {
        let raw = r#"{"reply":"Good luck \ud83d\ude00 ok"}"#;
        for n in 1..=raw.chars().count() {
            assert_eq!(streamed(raw, n), "Good luck 😀 ok", "pieces of {n} chars");
        }
    }

    #[test]
    fn common_json_escapes_decode_like_serde() {
        let json = r#"{"reply":"a\rb\fc\bd\/e"}"#;
        let want: R = serde_json::from_str(json).unwrap();
        assert_eq!(streamed(json, 7), want.reply);
    }

    #[test]
    fn a_cancelled_reply_keeps_its_words_but_does_not_parse() {
        let mut s = ReplyStream::default();
        let cut = ["{\"reply\": \"Multiply the ", "deriv", "atives and add"];
        let shown: String = cut.iter().filter_map(|p| s.feed(p)).collect();
        assert_eq!(shown, "Multiply the derivatives and add");
        let raw = cut.concat();
        assert_eq!(parse::<R>(&raw), Err(ReplyError::NoJson), "the rest is for the UI: the words so far stay on screen");
        assert_eq!(ReplyError::NoJson.to_string(), "the reply has no JSON object");
    }

    #[test]
    fn half_an_escape_at_the_cut_shows_the_words_before_it() {
        let mut s = ReplyStream::default();
        assert_eq!(s.feed("{\"reply\":\"caf\\u00"), Some("caf".into()));
        let mut t = ReplyStream::default();
        assert_eq!(t.feed("{\"reply\":\"end\\"), Some("end".into()), "a lone backslash");
    }

    #[test]
    fn nested_objects_and_text_around_the_json_still_parse() {
        #[derive(Deserialize, Debug, PartialEq)]
        struct N {
            reply: String,
            extra: Option<serde_json::Value>,
        }
        let n: N = parse("Sure!\n{\"extra\":{\"a\":{\"b\":1}},\"reply\":\"ok\"}\nHope that helps").unwrap();
        assert_eq!(n.reply, "ok");
        assert_eq!(n.extra.unwrap()["a"]["b"], 1);
        assert_eq!(parse::<R>("}{"), Err(ReplyError::NoJson), "closing brace before opening");
        assert_eq!(parse::<R>(""), Err(ReplyError::NoJson));
        assert_eq!(parse::<R>("<think>{\"reply\":\"x\"}"), Err(ReplyError::NoJson), "an unclosed think block hides everything");
        assert_eq!(parse::<R>(r#"{"reply":"a","reply2":"b"}"#), Ok(R { reply: "a".into() }), "unknown keys are ignored");
    }
}
