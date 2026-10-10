use std::collections::VecDeque;

pub trait Llm: Send {
    /// Streams tokens to `on_token`; returning false from it cancels.
    /// Returns the text produced so far.
    fn generate(
        &mut self,
        prompt: &str,
        schema: Option<&serde_json::Value>,
        max_tokens: u32,
        on_token: &mut dyn FnMut(&str) -> bool,
    ) -> Result<String, String>;

    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String>;
}

/// Replays canned replies, one per `generate`, and records the prompts.
#[derive(Default)]
pub struct FakeLlm {
    pub replies: VecDeque<String>,
    pub prompts: Vec<String>,
}

impl FakeLlm {
    pub fn new(replies: &[&str]) -> Self {
        Self { replies: replies.iter().map(|s| s.to_string()).collect(), prompts: vec![] }
    }
}

impl Llm for FakeLlm {
    fn generate(
        &mut self,
        prompt: &str,
        _schema: Option<&serde_json::Value>,
        _max_tokens: u32,
        on_token: &mut dyn FnMut(&str) -> bool,
    ) -> Result<String, String> {
        self.prompts.push(prompt.to_string());
        let reply = self.replies.pop_front().ok_or("no reply queued")?;
        let mut out = String::new();
        for word in reply.split_inclusive(' ') {
            out.push_str(word);
            if !on_token(word) {
                break;
            }
        }
        Ok(out)
    }

    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        // ponytail: length-only vectors, enough for plumbing tests; RAG tests bring their own.
        Ok(texts.iter().map(|t| vec![t.len() as f32]).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn streams_words_and_cancels() {
        let mut m = FakeLlm::new(&["one two three"]);
        let mut seen = vec![];
        let out = m
            .generate("p", None, 8, &mut |t| {
                seen.push(t.to_string());
                seen.len() < 2
            })
            .unwrap();
        assert_eq!(seen, ["one ", "two "]);
        assert_eq!(out, "one two ");
        assert_eq!(m.prompts, ["p"]);
        assert!(m.generate("p", None, 8, &mut |_| true).is_err());
    }
}
