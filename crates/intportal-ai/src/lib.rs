//! On-device AI logic that needs no model: the `Llm` trait, prompt budgets
//! and reply parsing. llama.cpp lives in `intportal-llm`, so Linux CI never
//! compiles it (ADR 0003).

pub mod assis;
pub mod gen;
pub mod intent;
pub mod llm;
pub mod models;
pub mod outline;
pub mod pdf;
pub mod prompt;
pub mod rag;
pub mod reply;
pub mod schema;
pub mod why;
