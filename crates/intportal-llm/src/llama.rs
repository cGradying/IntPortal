use crate::{take_utf8, threads_for, Device};
use intportal_ai::llm::Llm;
use llama_cpp_2::{
    context::params::{KvCacheType, LlamaContextParams, LlamaPoolingType},
    llama_backend::LlamaBackend,
    llama_batch::LlamaBatch,
    model::{params::LlamaModelParams, LlamaModel},
    sampling::LlamaSampler,
};
use std::{
    num::NonZeroU32,
    path::Path,
    sync::{Mutex, OnceLock},
};

const N_BATCH: usize = 512;

/// llama.cpp allows one backend per process, and the chat and embedding models
/// are loaded side by side, so they share it and it is never freed.
fn backend() -> Result<&'static LlamaBackend, String> {
    static BACKEND: OnceLock<LlamaBackend> = OnceLock::new();
    static INIT: Mutex<()> = Mutex::new(());
    let _one_at_a_time = INIT.lock().map_err(|e| e.to_string())?;
    if let Some(b) = BACKEND.get() {
        return Ok(b);
    }
    let b = LlamaBackend::init().map_err(|e| e.to_string())?;
    Ok(BACKEND.get_or_init(|| b))
}

pub struct Llama {
    backend: &'static LlamaBackend,
    model: LlamaModel,
    n_ctx: u32,
}

impl Llama {
    pub fn load(path: &Path, n_ctx: u32, device: Device) -> Result<Self, String> {
        let backend = backend()?;
        let layers = if device == Device::Gpu { 999 } else { 0 };
        let params = LlamaModelParams::default().with_n_gpu_layers(layers);
        let model = LlamaModel::load_from_file(backend, path, &params).map_err(|e| e.to_string())?;
        Ok(Self { backend, model, n_ctx })
    }

    fn params(&self) -> LlamaContextParams {
        // q8_0 KV cache needs flash attention (ADR 0003: fits the 4K budget on a phone).
        let threads = threads_for(std::thread::available_parallelism().map_or(4, |n| n.get()));
        LlamaContextParams::default()
            .with_n_threads(threads)
            .with_n_threads_batch(threads)
            .with_n_ctx(NonZeroU32::new(self.n_ctx))
            .with_n_batch(N_BATCH as u32)
            .with_flash_attention_policy(1 /* LLAMA_FLASH_ATTN_TYPE_ENABLED */)
            .with_type_k(KvCacheType::Q8_0)
            .with_type_v(KvCacheType::Q8_0)
    }
}

impl Llama {
    /// Reads `prompt` and `prefill`, then writes; the grammar has already seen the prefill's tokens.
    fn run(&mut self, prompt: &str, prefill: &str, schema: Option<&serde_json::Value>, max_tokens: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        let vocab = self.model.vocab();
        let mut toks = vocab.tokenize(prompt.as_bytes(), true, true);
        let given = if prefill.is_empty() { vec![] } else { vocab.tokenize(prefill.as_bytes(), false, false) };
        toks.extend(&given);
        if toks.len() as u32 + max_tokens > self.n_ctx {
            return Err(format!("prompt of {} tokens does not fit {} context", toks.len(), self.n_ctx));
        }
        let mut ctx = self.model.new_context(self.backend, self.params()).map_err(|e| e.to_string())?;
        let mut batch = LlamaBatch::new(N_BATCH, 1);
        let mut pos = 0i32;
        for chunk in toks.chunks(N_BATCH) {
            batch.clear();
            for (i, t) in chunk.iter().enumerate() {
                let last = pos as usize + 1 == toks.len();
                batch.add(*t, pos, &[0], last && i == chunk.len() - 1).map_err(|e| e.to_string())?;
                pos += 1;
            }
            ctx.decode(&mut batch).map_err(|e| e.to_string())?;
        }
        let mut samplers = vec![];
        if let Some(schema) = schema {
            let grammar = llama_cpp_2::json_schema_to_grammar(&schema.to_string()).map_err(|e| e.to_string())?;
            samplers.push(LlamaSampler::grammar(&self.model, &grammar, "root").map_err(|e| e.to_string())?);
        }
        samplers.push(LlamaSampler::greedy());
        let mut sampler = LlamaSampler::chain_simple(samplers);
        sampler.accept_many(&given); // the grammar continues from the prefill, it does not start over
        let (mut out, mut pending) = (String::new(), Vec::new());
        for _ in 0..max_tokens {
            let tok = sampler.sample(&ctx, batch.n_tokens() - 1);
            if vocab.is_eog(tok) {
                break;
            }
            pending.extend(vocab.token_to_piece(tok, false, None));
            let piece = take_utf8(&mut pending);
            out.push_str(&piece);
            if !piece.is_empty() && !on_token(&piece) {
                break;
            }
            batch.clear();
            batch.add(tok, pos, &[0], true).map_err(|e| e.to_string())?;
            pos += 1;
            ctx.decode(&mut batch).map_err(|e| e.to_string())?;
        }
        Ok(out)
    }
}

impl Llm for Llama {
    fn generate(&mut self, prompt: &str, schema: Option<&serde_json::Value>, max_tokens: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        self.run(prompt, "", schema, max_tokens, on_token)
    }

    fn generate_prefilled(&mut self, prompt: &str, prefill: &str, schema: Option<&serde_json::Value>, max_tokens: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        self.run(prompt, prefill, schema, max_tokens, on_token).map(|out| format!("{prefill}{out}"))
    }

    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        let params = self.params().with_embeddings(true).with_pooling_type(LlamaPoolingType::Mean);
        let mut ctx = self.model.new_context(self.backend, params).map_err(|e| e.to_string())?;
        let mut out = Vec::with_capacity(texts.len());
        for text in texts {
            let mut toks = self.model.vocab().tokenize(text.as_bytes(), true, false);
            toks.truncate(N_BATCH); // the first 512 tokens say what a long chunk is about; refusing it left it unsearchable
            let mut batch = LlamaBatch::new(N_BATCH, 1);
            for (i, t) in toks.iter().enumerate() {
                batch.add(*t, i as i32, &[0], true).map_err(|e| e.to_string())?;
            }
            ctx.clear_kv_cache();
            ctx.decode(&mut batch).map_err(|e| e.to_string())?;
            let v = ctx.embeddings_seq_ith(0).map_err(|e| e.to_string())?;
            let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt().max(f32::EPSILON);
            out.push(v.iter().map(|x| x / norm).collect());
        }
        Ok(out)
    }
}
