# On-device AI (IntAssis): working notes

For the AI role. The decisions are in [ADR 0003](adr/0003-on-device-ai-llama-cpp.md); this file holds what you need to run and extend it.

## Layout

| Path | What |
|---|---|
| `crates/intportal-ai` | Pure Rust, no model. `llm` (trait, `FakeLlm`), `prompt` (budgets, chat templates), `reply` (strip `<think>`, parse JSON), `schema`, `rag`, `gen` (flashcards in batches), `pdf`, `models` (catalog, RAM gate), `intent`, `assis` (one chat turn), `why`, `outline`. |
| `crates/intportal-llm` | llama.cpp behind `Llm`. A stub on Linux. `download` (resume, SHA check), `mem`, `backup`. |
| `spikes/s1-llama` | The A0 spike and its `REPORT.md`. Not wired into the app. |

## Rules that came out of measuring

- **Rules pick the action, the schema forces it.** Gemma 3 1B never proposed an action on its own. `intent::detect` decides, and the schema then allows only that action. The model fills a short `text`.
- **The model never computes dates.** `intent::resolve_when` reads "bukas", "sa Lunes". When no day is named, the model picks `d0`..`d13` from a table.
- **Exact questions skip the model.** Due, classes today and grades are answered from the app's data.
- **Give the model a limit on every string** (`maxLength`), and clean what comes back (`outline::clean`). A 1B model runs on into other scripts otherwise.
- **One short call per unit** (a week, a batch of 12 then 6 cards). Whole-term outputs collapse into week 1.
- The default chat model is `models::DEFAULT_CHAT` (Gemma 3 1B). Its prompt template is `Template::Gemma`; Qwen uses ChatML with an empty think block.

## Running it

Models are downloaded by hand for development (the app does it through `download`); keep them outside git and check the SHA-256 in `models.rs`.

```bash
# schema-valid replies on 20 Taglish prompts, tokens/sec
cargo run --release -p intportal-llm --example eval -- <chat.gguf>
# does the embedding model rank notes sensibly
cargo run --release -p intportal-llm --example embed -- <nomic.gguf>
# the assistant, "Why?" and a title guide on a real model
cargo run --release -p intportal-llm --example assis -- <gemma.gguf>
```

Add `open` to `eval` for the Taglish open-question set (below). Pass `cpu` as the last argument to `eval` for CPU only. Metal is on by default on Apple targets; the iOS simulator's Metal is software and slow, so measure speed on a CPU run or the user's iPhone (`scripts/phone.sh`, run by the user).

## Open-question eval (Taglish, grounded vs unsupported)

`eval -- <chat.gguf> open` asks 15 questions through the same prompt shape as `assis` for an open question (system text, a "From the student's notes" section, grammar-forced `{"reply": ...}`, 300 tokens). Three seeded notes are always in the prompt (inorder traversal, Math 101 quiz and passing mark, a finals plan). 8 questions are answered by a note; 7 are not (no grade, no timetable, preorder traversal, thesis deadline, PUP president, tuition, "Okay lang ba ako sa Math?") and should get "I don't know".

Checks are string heuristics, so read the printed replies too: **grounded** = reply contains an expected keyword of the right note; **refusal** = reply contains a phrase like "hindi ko alam" / "I don't know" / "not familiar"; latency is wall time per reply.

Run 2026-10-15, Apple Silicon, Metal, release build, one run each (other builds were running, so latency is rough):

| Model | Valid JSON | Grounded | Refusals | Median latency |
|---|---|---|---|---|
| Gemma 3 1B it Q4_K_M | 15/15 | 7/8 | 5/7 | 2.2 s (max 4.5 s) |
| Qwen3 1.7B Q4_K_M | 15/15 | 8/8 | 4/7 | 1.7 s (max 3.0 s) |

What the replies showed:

- Grammar makes the JSON valid for both. The risk is the content.
- Both invent on "Okay lang ba ako sa Math?" (the Math 101 note tempts them into advice). Gemma also answered the Physics grade with the Math 101 passing mark; Qwen answered "what time is class tomorrow" with "Monday" (the quiz note) and described preorder with the inorder text.
- Gemma misses more grounded answers and its Tagalog slips ("lilang sa Monday", an off-topic BST sentence in a refusal); Qwen answers in English to Taglish questions.
- So "answer from the facts only" is not enough at 1B-2B. Answers that depend on data the app has (grades, classes, due) must stay exact and skip the model, as `assis` already does; for the rest, a relevance floor on RAG hits (`rag::FLOOR`) matters more than the model choice.

## Android build

llama.cpp needs a flag at minSdk 24 (`posix_madvise`); see `spikes/s1-llama/REPORT.md`. Set `ANDROID_NDK_ROOT`, and delete the cached cmake build after changing flags.

## Android findings (emulator, Android 15 arm64, 2.5 GB RAM, debug build)

- **`app_data_dir()` is the app's data root** (`/data/user/0/ph.intportal.app`), not `files/`. Models go in `models/` under it. The manifest has `allowBackup="false"`, so nothing there is backed up.
- To test with a model, push it with `adb push` to `/data/local/tmp`, then `adb shell run-as ph.intportal.app cp` it into `models/` (debug builds only; release builds are not debuggable).
- Launch, the You card, waking the model (about 1 GB resident) and an exact answer ("Ano ang due ko?") all worked. Free-form generation was very slow: a debug build compiles llama.cpp unoptimised, so judge speed only from a release build on a real phone.
- `adb install` over a different signing key fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; the emulator may hold another session's debug app, so check before uninstalling.
- Settled: the Android WebView does open a file picker for `<input type=file>` is **not** tested yet (needed for PDFs).

## Not done yet

Cards from a note or PDF in DeckPage, the syllabus guide in SubjectPage (UI #92, needs Core #93 `Plan.guide`), and the phone checks: Metal speed and memory on a real iPhone, a release APK run on Android, and the Android file picker.

Done: RAG also indexes deck cards (`card:<deck id>`) and syllabus text (`plan:<code>`); the chat's source chips can carry those keys (the UI opens only notes so far). Done in spec [020-ai](specs/020-ai.md): RAG wired into `ai_ask` with sources, streamed replies, a chat that survives restarts, Ask AI in a note, the Light or With-AI choice at first run.

## EmbeddingGemma-2 via ONNX spike

Throwaway spike for [#157](https://github.com/cGradying/intportal-app/issues/157), route B (branch `spike/embeddinggemma2-onnx`, never for main). Question: can EmbeddingGemma-2 run in the app through ONNX Runtime instead of waiting for a `llama-cpp-2` bump? Code: `crates/intportal-llm/examples/onnx_embed.rs` (dev-dependencies `ort =2.0.0-rc.15` with `coreml`, `tokenizers 0.23`; macOS only). Labels: **measured** (run here), **docs** (verified from crate source or ONNX Runtime docs), **inferred** (not run).

### Setup (measured)

- Source `onnx-community/embeddinggemma-2-ONNX` (Apache-2.0), kept outside git in `~/Library/Application Support/PUPSISPortal/models/onnx-eg2/`. Every LFS sha256 and size matched the Hugging Face API (`model_q4`, `model_q4f16`, `model_quantized`, `tokenizer.json`). `model_q4.onnx_data` is 174,028,800 bytes, sha256 `c3975f2d...`.
- The repo is the multimodal one (vision and audio encoders ship as separate files). The text model `onnx/model_*.onnx` (+ `.onnx_data`) is self-contained and has the **`sentence_embedding` output [batch, 768]** (already pooled and projected; I L2-normalise it) beside `last_hidden_state`. Inputs: `input_ids`, `attention_mask` (int64) and three required `image_features`/`video_features`/`audio_features` float inputs of shape `[n, 512]`; for text only feed `[0, 512]` (CPU) or one unused zero row (CoreML rejects zero-element inputs).
- `tokenizer.json` through the `tokenizers` crate adds BOS and EOS (`[2, ..., 1]`). Prefixes: `title: none | text: {chunk}` for notes, `task: search result | query: {q}` for questions.
- Sanity: the model card's own example reproduces exactly (Mars 0.854, Saturn 0.783, Jupiter 0.752, Venus 0.684 on q4), so tokenizer, prefixes, output and normalisation are right. No NaN or inf in any variant, including q4f16.

### Retrieval: the `eval open` set (measured)

3 seeded notes (one 700-char chunk each, `rag::chunk_text`), 8 supported and 7 unsupported questions, best-hit cosine per question. Apple Silicon Mac, release build, batch 1, 18 short texts x3 after a warm-up. nomic uses the app's own `Llama::embed` (a fresh context per call).

| Model | File | Dim | Top-1 on supported | Best hit, supported (min / mean) | Best hit, unsupported (max / mean) | Min sup - max unsup | ms per embed | Load | Peak RSS |
|---|---|---|---|---|---|---|---|---|---|
| nomic v1.5 Q4_K_M, Metal | 84.1 MB | 768 | 8/8 | 0.617 / 0.697 | 0.629 / 0.568 | -0.012 | 13.1 | 0.19 s | n/m |
| nomic v1.5 Q4_K_M, CPU | 84.1 MB | 768 | 8/8 | 0.618 / 0.697 | 0.635 / 0.575 | -0.017 | 26.0 | 0.27 s | 256 MB |
| EG2 `q4`, ORT CPU | 174.5 MB | 768 | 8/8 | 0.688 / 0.775 | 0.727 / 0.660 | -0.039 | 59-71 (8 threads 59, 4 or 6: 68, 2: 83) | 0.8-1.7 s | 536 MB |
| EG2 `q4f16`, ORT CPU | 157.4 MB | 768 | 8/8 | 0.688 / 0.775 | 0.727 / 0.660 | -0.039 | 82 | 1.0 s | 549 MB |
| EG2 `quantized` (8-bit), ORT CPU | 314.2 MB | 768 | 8/8 | 0.699 / 0.777 | 0.732 / 0.657 | -0.033 | 253 | 0.8 s | 638 MB |
| EG2 `q4`, CoreML (NeuralNetwork) | 174.5 MB | 768 | 8/8 | same as CPU | same | -0.039 | 121 | 1.8 s | n/m |
| EG2 `q4`, CoreML (MLProgram) | 174.5 MB | 768 | 8/8 | same as CPU | same | -0.039 | 1298 | 13.3 s | n/m |
| EG2 `q4f16` / `quantized`, CoreML | | 768 | 8/8 | same as CPU | same | | 71 / 210 | 0.8 / 2.4 s | n/m |

(n/m = not measured. Timings on a loaded Mac, one run each: expect +-15%. The first `q4` load after download was 4.9 s with ORT's auto-picked CoreML.)

What it says:

- **Ranking is no better than nomic on this set.** Both put the right note first 8/8 and order 54 of 56 supported/unsupported pairs correctly. This set is too easy and too small (one chunk per note) to show EG2's multilingual gain; the Taglish table in #157 needs a bigger set (real notes, distractors).
- **A floor.** Neither model separates the sets by min/max (negative margin: one weak supported question vs one tempting unsupported one, "Ano ang preorder traversal?"). EG2 scores run higher (supported mean 0.775, unsupported 0.660), so the old 0.5 would keep every unsupported hit, as it does for nomic. On this set, `FLOOR` 0.73 would keep 7/8 supported and 0/7 unsupported; nomic's best floor (0.625) keeps 7/8 and leaks 1. That is tuned on 15 questions, so treat 0.70-0.73 as a starting point and recalibrate on the real Taglish set.
- **q4f16 = q4.** Cosine between their embeddings is 1.0000 (min over the 18 texts), and `q4f16` is slower on CPU (82 vs 71 ms), so the 17 MB saving is not worth it. `quantized` differs from q4 by cosine 0.984 (mean), is 4x slower and 1.8x bigger, with no ranking gain here.
- **CoreML does not help.** Same scores as CPU, 1.2x to 20x slower (MLProgram recompiles per sequence length: 1.3 s per embed). Keep the CPU provider; set `with_auto_device(PreferCPU)` because ORT's default on macOS registers CoreML on its own (it failed at first on the zero-element input).
- **Cost vs nomic:** 2x the file, 2x to 5x slower per embed on CPU, 2x the RAM (536 MB peak RSS; the 174 MB file expands as ORT prepacks weights). A 25-chunk note re-index is about 1.5-1.8 s on a Mac; on a phone CPU expect several times that (inferred).

### Mobile feasibility

- **Targets (docs).** `ort-sys 2.0.0-rc.15` `build/download/dist.tsv` lists prebuilt static ONNX Runtime 1.31 for `aarch64-apple-ios` and `aarch64-apple-ios-sim` (both `+coreml`), `aarch64-linux-android` and `x86_64-linux-android` (both `+nnapi`), `aarch64-apple-darwin` (`+coreml`). The `download-binaries` default feature fetches them from `cdn.pyke.io` at build time and checks sha256. **Not in the list: `armv7-linux-androideabi`** (our `.cargo/config.toml` carries armv7 flags) and `x86_64-apple-ios`. iOS can instead link an `onnxruntime.xcframework` (`ORT_IOS_XCFWK_PATH`); any target can use your own static build (`ORT_LIB_LOCATION`). I did **not** build for iOS or Android (out of scope), so linking there is unproven.
- **Android C++ runtime (docs + inferred).** `ort-sys` links `c++_shared` by default on Android (`ORT_CXX_STDLIB` overrides it); our llama.cpp uses `android-static-stdcxx` so the app ships one `.so`. Mixing both needs `ORT_CXX_STDLIB=c++_static` plus a check that the prebuilt library was built for it (inferred, untested).
- **Build offline.** The prebuilt archives are fetched at build time: CI and offline builds need the cache (`~/Library/Caches/ort.pyke.io`) or a self-hosted copy. Pre-linking `tokenizers` adds `onig` (C), one more native dependency; `tokenizers` with `fancy-regex` avoids it (untried).
- **Binary growth.** Measured on macOS arm64, release, LTO, stripped: a program that only creates an ORT session is **19.1 MB** (prebuilt `libonnxruntime.a` is 83.5 MB, full operator set plus the CoreML provider); `tokenizers` alone is 2.8 MB; the whole llama.cpp embed example is 5.6 MB. So ORT roughly **+19 MB, tokenizers +2-3 MB, about 3.5x the entire current llama stack**. iOS and Android prebuilt archives are about the same size as the macOS one (compressed 10.0 MB iOS, 11.2 MB Android vs 9.7 MB macOS, measured with HEAD), so expect **+15-20 MB** on each (inferred). ONNX Runtime docs list a 1.18 prebuilt Android arm64 `libonnxruntime.so` at 16.3 MB uncompressed against 4.0 MB for a custom `--minimal_build=extended` with only ResNet50's operators (docs); doing that for Gemma needs our own ORT build per platform and an ORT-format model (inferred: not tried, extra CI cost).
- **Two engines.** ORT would be a second C++ inference runtime beside llama.cpp, each with its own thread pools and allocator; the `LlamaBackend` once-per-process rule in `llama.rs` does not cover ORT (inferred, nothing clashed on the Mac). The two-slot design in `src-tauri/src/ai.rs` survives: a slot holds a `Box<dyn Llm>` keyed by `Kind`, so an ORT embedder is one more `Llm` impl in the embed slot. Needed changes: `load_into` calls `Llama::load` unconditionally (pick the backend by model format), and `models.rs`/`download.rs` assume one file per model while an ONNX model is `.onnx` plus `.onnx_data` (inferred from reading the code, not tried). Memory is the real cost: ORT's ~0.5 GB beside the chat model's ~1 GB resident on a 4 GB phone.

### Verdict

Route B works on the Mac: the right vectors, the model card's numbers, no NaNs, full-quality ranking equal to nomic on this set. It is a poor fit for the phone: +15-20 MB per platform, +0.5 GB RAM, 2x-5x slower than nomic, a second engine, no armv7, and a CI download dependency. Only worth it if route C (llama.cpp) stays blocked for long; if llama.cpp lands `gemma-embedding2` in a release, the GGUF (310 MB Q8_0) avoids the second engine. Use `q4` (not `q4f16`) if this route is taken.

To run: `cargo rustc --release -p intportal-llm --example onnx_embed -- -C link-arg=$(clang -print-resource-dir)/lib/darwin/libclang_rt.osx.a` (ORT's CoreML objects reference `___isPlatformVersionAtLeast` from compiler-rt), then `onnx_embed onnx <model-dir> q4 cpu [threads]` or `onnx_embed nomic <gguf> [cpu]`.
