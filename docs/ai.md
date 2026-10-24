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

## EmbeddingGemma-2 spike (issue #157, branch `spike/embeddinggemma2`, NOT for main)

Throwaway numbers for swapping the nomic embedder. `Cargo.toml` here has a `[patch.crates-io]` pointing `llama-cpp-2` and `llama-cpp-sys-2` at `willsheldon/llama-cpp-rs` branch `llama-cpp-bump-gemma-embedding2` (utilityai PR #1175, commit cb98c630, crate version 0.1.161, llama.cpp v0.7.0). It builds, and `gemma-embedding2` loads. Run: `cargo run --release -p intportal-llm --example embed_spike -- <nomic.gguf> <embeddinggemma-2-Q8_0.gguf> [nomic|eg2]`. The model file (309,855,456 bytes) matched the sha256 in the issue.

Set: the 3 seeded notes of `eval.rs` cut into 8 sentence chunks, and the 15 open questions (8 supported, 7 unsupported). nomic uses `search_document:` / `search_query:`; EmbeddingGemma-2 uses `title: none | text: {doc}` / `task: search result | query: {q}`. Mean pooling, L2-normalized, Metal, release build, M-series Mac, one machine, other builds running at the same time. Gold for top-1 is the sentence chunk that holds the answer (a few questions accept two or three).

| | nomic v1.5 Q4_K_M | EmbeddingGemma-2 Q8_0 |
|---|---|---|
| File size | 84 MB | 310 MB |
| Dimension | 768 | 768 |
| Top-1 correct, supported (8 chunks) | 7/8 | 7/8 |
| Top-1 correct, supported (3 whole notes, as the app chunks today) | 8/8 | 8/8 |
| Best hit, supported questions: min / median | 0.621 / 0.697 | 0.719 / 0.838 |
| Best hit, unsupported questions: max / median | 0.630 / 0.594 | 0.757 / 0.681 |
| Margin (min supported minus max unsupported) | -0.010 | -0.038 |
| Model load, warm (two runs) | 168 and 210 ms | 911 and 602 ms |
| ms per embed (new context each call, median of 26) | 11.0 and 20.8 | 47.7 and 21.0 |
| 256-d truncation, top-1 (8 chunks) | 8/8 | 7/8 |
| 256-d margin (8 chunks / 3 notes) | -0.012 / 0.000 | -0.031 / -0.059 |

Load and ms are noisy (a build was running in run 1; nomic's very first cold load was 10 s, mostly backend and Metal shader setup, and does not repeat). Treat the two models as about the same speed here.

What it showed:

- **No floor separates the classes on either model**: the best unsupported hit (nomic 0.630 "thesis deadline"; EG2 0.757 "preorder traversal") scores above the weakest supported hit. Unsupported questions that touch a note's topic ("Okay lang ba ako sa Math?", "preorder traversal") score high on both. RAG can only drop the clearly unrelated ones; the prompt still has to say "I don't know".
- Both miss the same question at chunk level ("Kailan ang quiz sa Math 101?" ranks the "quiz covers limits" chunk over "moved the quiz to Monday"); with whole notes both get 8/8.
- EG2 scores everything higher (about +0.1 to +0.15), so the same 0.5 floor would let all 7 unsupported through (leak 7/7; nomic at 0.5 also leaks 7/7, so 0.5 is already no filter on this set).
- Floor sweep, EG2, 8 chunks (keep = supported kept of 8, leak = unsupported passed of 7): 0.65: 8 and 5; 0.70: 8 and 2; 0.75: 6 and 1; 0.80: 4 and 0. nomic: 0.55: 8 and 4; 0.60: 8 and 2; 0.65: 6 and 0.
- **Suggested `FLOOR` for EG2: 0.70** (keeps all 8 supported, drops 5 of 7 unsupported; the 2 leaks are the on-topic ones). That is the same trade nomic makes at 0.60. Going higher than 0.72 starts losing supported hits. For nomic the current 0.5 could be raised to 0.60 on the same evidence, a separate fix.
- **256-d truncation (first 256 dims, renormalized) does not hurt top-1** on this set (EG2 7/8 either way; nomic even 8/8) and shifts scores up about 0.03, so use floor 0.72-0.73 if it is used. On whole notes the margin gets worse for EG2 (-0.032 to -0.059), so keep 768-d unless storage matters. The set is tiny (8 chunks, 15 questions): a quality claim for EG2 over nomic is **not** supported by it; the multilingual gain the issue hopes for needs a bigger Filipino set.
- Not changed: `rag.rs` still uses nomic prefixes and FLOOR 0.5; `models.rs` untouched. The patch also moves the chat engine to llama.cpp v0.7.0, which was not tested here (mobile builds were not run).
