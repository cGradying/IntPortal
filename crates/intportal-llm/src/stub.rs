use intportal_ai::llm::Llm;
use std::path::Path;

pub struct Llama;

const NO: &str = "on-device models are not available on this platform";

impl Llama {
    pub fn load(_path: &Path, _n_ctx: u32, _device: crate::Device) -> Result<Self, String> {
        Err(NO.into())
    }
}

impl Llm for Llama {
    fn generate(&mut self, _: &str, _: Option<&serde_json::Value>, _: u32, _: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        Err(NO.into())
    }
    fn embed(&mut self, _: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        Err(NO.into())
    }
}
