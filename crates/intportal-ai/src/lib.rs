//! On-device AI logic that needs no model: the `Llm` trait, prompt budgets
//! and reply parsing. llama.cpp lives in `intportal-llm`, so Linux CI never
//! compiles it (ADR 0003).

pub mod llm;
pub mod prompt;
pub mod reply;
