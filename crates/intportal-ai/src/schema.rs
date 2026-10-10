use serde_json::{json, Value};

/// `{reply, actions:[{kind, text}]}` where `kind` can only be one of `kinds`,
/// so the model can't invent an action. Subject codes and date ids join the
/// enums when IntAssis needs them (A9).
pub fn reply_schema(kinds: &[&str]) -> Value {
    json!({
        "type": "object",
        "properties": {
            "reply": {"type": "string"},
            "actions": {"type": "array", "items": {
                "type": "object",
                "properties": {"kind": {"enum": kinds}, "text": {"type": "string"}},
                "required": ["kind", "text"]
            }}
        },
        "required": ["reply", "actions"]
    })
}

#[derive(serde::Deserialize, Debug)]
pub struct Reply {
    pub reply: String,
    pub actions: Vec<Action>,
}

#[derive(serde::Deserialize, Debug)]
pub struct Action {
    pub kind: String,
    pub text: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kinds_are_the_only_choices() {
        let s = reply_schema(&["add_note", "none"]);
        assert_eq!(s["properties"]["actions"]["items"]["properties"]["kind"]["enum"], json!(["add_note", "none"]));
    }
}
