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
                    let hex: String = chars.by_ref().take(4).collect();
                    match u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32) {
                        Some(ch) if hex.len() == 4 => out.push(ch),
                        _ => break, // cut mid-escape, or half of a surrogate pair
                    }
                }
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
}
