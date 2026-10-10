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
}
