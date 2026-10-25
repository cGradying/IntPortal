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

Add `open` to `eval` for the Taglish open-question set (below), and `open full` to send each question through `assis::answer` (rules first, then the model) instead of straight to the model. Pass `cpu` as the last argument to `eval` for CPU only. Metal is on by default on Apple targets; the iOS simulator's Metal is software and slow, so measure speed on a CPU run or the user's iPhone (`scripts/phone.sh`, run by the user).

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

### Saying "I don't have that" (issue #138)

Two changes, measured one at a time on the same 15 questions, one run each, Apple Silicon, Metal, release build (latency omitted: other builds were running):

1. **Prompt rule** (`assis::SYSTEM`): "Answer only from the facts and notes below. If they do not contain the answer, say so in one sentence ... and say what you can see instead. Never guess ..." The eval now uses `assis::SYSTEM`, not a copy.
2. **No-data path** (`assis::no_data`, no model call): a question about the student's own data that nothing the app holds can answer gets a fixed EN/Filipino reply. It fires for (a) a class question about another day ("bukas"), since the app only holds today's classes; (b) "Okay lang ba ako sa <subject>?" when that subject has no grading; (c) first-person questions about room, professor, units, tuition, section and the like with no note hits and no open note. Everything else still reaches the model.

| Model | Run | Grounded | Refusals |
|---|---|---|---|
| Gemma 3 1B | before (old prompt, model only) | 7/8 | 5/7 |
| Gemma 3 1B | new prompt, model only | 6/8 | 7/7 |
| Gemma 3 1B | new prompt + no-data path (`open full`) | 2/8 | 7/7 |
| Qwen3 1.7B | before | 8/8 | 4/7 |
| Qwen3 1.7B | new prompt, model only | 8/8 | 5/7 |
| Qwen3 1.7B | new prompt + no-data path (`open full`) | 5/8 | 6/7 |

What I read in the printed replies:

- The prompt alone moves Gemma to 7/7 refusals, but it also says "I don't have that" for the study-block question the Finals note answers, and its "inorder traversal" reply (right in substance, no "left"/"right" keyword) counts as a miss, so Gemma's real grounded rate is about 7/8 and a hair worse than before. Qwen only gained one refusal.
- Qwen still invents on "what time is class tomorrow" ("Monday" from the quiz note) and describes preorder with the inorder note. An extra prompt line saying a note about something else is no answer changed nothing, so it was dropped.
- In `open full` the no-data path catches the class-time question and "Okay lang ba ako sa Math?". The thesis-deadline, Physics-grade and Math-quiz questions are caught by the older rules (Due/Grades), which print "nothing is due" / "no grading set up". Those canned replies are counted as refusals by the heuristic (the list now includes them).
- The grounded drop in `open full` is the rules, not the model: the eval seeds no deadlines or grades, so "Kailan ang quiz sa Math 101?" and "Ano ang passing sa Math 101?" hit the Due and Grades rules and get "nothing is due" / "no grading", never reaching the note. In the app a real schedule fills those lists. Questions the model answers (inorder, finals plan) were unchanged for Qwen; Gemma misses two on heuristics, as above.
- Left: Qwen on preorder (a near-miss note). Only a per-note relevance floor can fix that and `eval` has no retrieval step, so it is not measured (lever 3 not tried).

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
