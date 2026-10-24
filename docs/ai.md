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

## Retrieval eval: nomic vs EmbeddingGemma-2 (60+ questions)

Issue #157, branch `spike/eg2-retrieval-eval` (on top of `spike/embeddinggemma2`, NOT for main). Rerun: `cargo run --release -p intportal-llm --example embed_eval -- <nomic.gguf> <embeddinggemma-2-Q8_0.gguf>` (about 10 s once built; deterministic, two runs gave identical output). Every number below is copied from that script's output.

Set (`crates/intportal-llm/examples/data/notes.json`, `questions.json`): 32 notes (Data Structures, Math, Physics, Organic Chem, General Chem, Filipino, History, NSTP, Accounting, a reminders note), English, Filipino and Taglish, cut by the app's own `rag::chunk_text` into 37 chunks (6 notes are longer than 700 chars). It has near-duplicates (inorder / preorder / postorder; SN1-SN2 / E1-E2; derivatives / limits) and misleading shared words (tree planting vs tree, bond in chemistry vs bonds payable, power rule vs power in Physics, "balance" in accounting vs balanced trees, cashier in a queue example vs the tuition reminder). 90 questions: 58 in-scope (one answering note each: 21 English, 14 Tagalog/Taglish, 4 typos, 6 keyword-only, 13 paraphrases that share few or no words with the note) and 32 out-of-scope, 8 per kind: **a** general knowledge ("capital of Peru", "sino si Jose Rizal"), **b** the student's own data ("my Physics midterm score"), **c** on-topic-looking but absent ("explain AVL rotations", "ano ang pokus ng pandiwa", "magkano ang tuition"), **d** chit-chat or injection. Prefixes: nomic `search_document:` / `search_query:`; EG2 `title: none | text:` / `task: search result | query:`. Cosine on unit vectors; a note's score is its best chunk; best hit = best note score.

| | nomic v1.5 Q4_K_M | EmbeddingGemma-2 Q8_0 |
|---|---|---|
| In-scope top-1 (58) | 46 (79%) | 54 (93%) |
| In-scope top-3 | 52 (90%) | 57 (98%) |
| Top-1 by style en / tl / typo / kw / para | 20/21, 10/14, 3/4, 4/6, 9/13 | 21/21, 13/14, 4/4, 5/6, 11/13 |
| Best hit, in-scope: min / median / max | 0.474 / 0.708 / 0.859 | 0.620 / 0.760 / 0.838 |
| Best hit, OOS a general: min / median / max | 0.515 / 0.627 / 0.710 | 0.532 / 0.605 / 0.688 |
| Best hit, OOS b own data | 0.619 / 0.635 / 0.658 | 0.639 / 0.696 / 0.745 |
| Best hit, OOS c on-topic absent | 0.574 / 0.629 / 0.745 | 0.651 / 0.682 / 0.821 |
| Best hit, OOS d chit-chat | 0.492 / 0.617 / 0.662 | 0.567 / 0.642 / 0.690 |
| **AUC** in-scope vs all OOS | **0.838** | **0.913** |
| AUC vs a / b / c / d | 0.841 / 0.845 / 0.778 / 0.890 | 0.985 / 0.875 / 0.812 / 0.981 |
| Best single FLOOR (max balanced accuracy) | **0.674** | **0.707** |
| Recall / false-accept / balanced acc at that floor | 74.1% / 6.2% / 0.839 | 87.9% / 12.5% / 0.877 |
| False-accept at that floor, a / b / c / d | 12% / 0% / 12% / 0% | 0% / 12% / 38% / 0% |
| 5-fold CV balanced acc of the floor | 0.793 | 0.862 |
| Recall at false-accept <= 5% / <= 10% / <= 20% | 48.3% / 74.1% / 81.0% | 56.9% / 82.8% / 87.9% |
| Recall at false-accept 0% | 25.9% (floor 0.751) | 12.1% (floor 0.821) |
| Current FLOOR 0.5 | recall 98.3%, false-accept 96.9% | recall 100%, false-accept 100% |
| AUC of the margin (best minus 2nd note) alone | 0.737 | 0.845 |
| Margin + floor rule, CV balanced acc (floor alone) | 0.793 (0.793) | 0.827 (0.862) |

ROC (accept if best hit >= floor; recall = in-scope accepted; FA = out-of-scope accepted). The full per-model table is printed by the script; 10 evenly spaced floors:

| nomic floor | recall | FA | bal. acc | | EG2 floor | recall | FA | bal. acc |
|---|---|---|---|---|---|---|---|---|
| 0.474 | 100.0% | 100.0% | 0.500 | | 0.532 | 100.0% | 100.0% | 0.500 |
| 0.517 | 98.3% | 93.8% | 0.523 | | 0.566 | 100.0% | 93.8% | 0.531 |
| 0.560 | 94.8% | 90.6% | 0.521 | | 0.600 | 100.0% | 84.4% | 0.578 |
| 0.603 | 91.4% | 68.8% | 0.613 | | 0.634 | 98.3% | 75.0% | 0.616 |
| 0.645 | 82.8% | 25.0% | 0.789 | | 0.668 | 96.6% | 40.6% | 0.780 |
| 0.688 | 60.3% | 6.2% | 0.770 | | 0.702 | 87.9% | 15.6% | 0.862 |
| 0.731 | 34.5% | 3.1% | 0.657 | | 0.736 | 67.2% | 6.2% | 0.805 |
| 0.774 | 13.8% | 0.0% | 0.569 | | 0.770 | 44.8% | 3.1% | 0.709 |
| 0.816 | 3.4% | 0.0% | 0.517 | | 0.804 | 20.7% | 3.1% | 0.588 |
| 0.859 | 1.7% | 0.0% | 0.509 | | 0.838 | 1.7% | 0.0% | 0.509 |

Paired: top-1 differs on 10 questions, only nomic right on 1, only EG2 right on 9. AUC difference EG2 minus nomic +0.075, bootstrap (2000 paired resamples of the questions) 95% interval [+0.001, +0.144], so the gain is real but the interval just clears zero.

**Conclusion.**

- **Retrieval: EG2 is better.** 54/58 vs 46/58 top-1 (+14 points), 57 vs 52 top-3. Almost all of the gain is Filipino and Taglish, typos and paraphrases (tl 13/14 vs 10/14, para 11/13 vs 9/13, typo 4/4 vs 3/4); on plain English both are about equal (21/21 vs 20/21). Its four remaining misses are "left, node, right" (preorder vs inorder), "Zaitsev", a nose-bleed paraphrase that lands on the Filipino verb note, and "when do two keys end up in the same bucket" (lands on the BST note).
- **Rejecting out-of-scope questions: better, by a smaller and uneven margin.** AUC 0.913 vs 0.838. EG2 separates general knowledge (0.985) and chit-chat/injection (0.981) from notes very well. It is only a little better on own-data questions (0.875 vs 0.845) and on on-topic-but-absent (0.812 vs 0.778). Those two kinds stay the problem on both models: "ano ang pokus ng pandiwa" scores 0.821 on EG2 (above many real hits) because the pandiwa note names that topic, and "ilan na ang absent ko sa NSTP" / "what is my GWA" both hit the NSTP note at 0.7+. A floor cannot remove these; the system prompt's "I don't know" still has to.
- **A floor drops only the clearly unrelated.** With the best single floor, EG2 keeps 88% of in-scope questions and lets 12.5% of out-of-scope through (38% of the on-topic-absent ones); nomic keeps 74% and lets 6.2% through. Compare at equal false-accept instead: at <=10% EG2 keeps 82.8% vs nomic 74.1%, at <=5% 56.9% vs 48.3%. Only at 0% false-accept is nomic better (25.9% vs 12.1%), and that point rests on one question.
- **FLOOR to use: nomic 0.67 (not 0.5; 0.5 accepts 97% of out-of-scope), EmbeddingGemma-2 0.71** (0.72-0.74 if wrong answers hurt more than missed ones: 0.736 gives 67% recall at 6% false-accept). The earlier 15-question spike suggested 0.70 for EG2 and 0.60 for nomic; EG2 is consistent, nomic's suggestion was low.
- **Margin between best and second-best note does not help.** Alone it separates worse than the score (AUC 0.737 / 0.845), and adding it to the floor never beats the floor alone; the best margin found was 0.000 on both models, and 5-fold CV of the two-parameter rule is lower for EG2 (0.827 vs 0.862) and equal for nomic. Near-duplicate notes make the margin small for good answers too.

**Caveats.** One author wrote the notes and the questions, after seeing the earlier spike's failures, so they lean toward the hard cases; 58 + 32 questions is small (one question moves recall by 1.7 points and a kind's false-accept by 12 points per question); thresholds are fitted on the same questions (the CV numbers show the optimism: 0.839 to 0.793 for nomic, 0.877 to 0.862 for EG2). Notes are short, so chunking changes only 6 of them. Students' real notes are messier and longer. Retrieval quality is only half of #157: file size (310 MB vs 84 MB), the patched llama.cpp for the mobile builds, and speed still need their own checks. Treat this as support for switching, not proof of a particular floor; re-tune on real student notes before shipping.
