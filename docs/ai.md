# On-device AI (IntAssis): working notes

For the AI role. The decisions are in [ADR 0003](adr/0003-on-device-ai-llama-cpp.md); this file holds what you need to run and extend it.

## Layout

| Path | What |
|---|---|
| `crates/intportal-ai` | Pure Rust, no model. `llm` (trait, `FakeLlm`), `prompt` (budgets, chat templates), `reply` (strip `<think>`, parse JSON), `schema`, `rag`, `gen` (flashcards in batches), `pdf`, `models` (catalog, RAM gate), `intent`, `persona` (how LAR talks: the system text, the few-shot turns, the lead-ins of rule answers), `assis` (one chat turn), `why`, `outline`. |
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
cargo run --release -p intportal-llm --example embed -- <embeddinggemma-2-Q8_0.gguf> [n_ctx] [cpu]
# nomic vs EmbeddingGemma-2 on 90 retrieval questions (about 10 s), and the FLOOR table
cargo run --release -p intportal-llm --example embed_eval -- <nomic.gguf> <embeddinggemma-2-Q8_0.gguf> [none]
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

1. **Prompt rule** (`assis::SYSTEM`, since #165 `persona::system`): "Answer only from the facts and notes below. If they do not contain the answer, say so in one sentence ... and say what you can see instead. Never guess ..." The eval uses the same text as the app, not a copy.
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

## LAR's voice (issue #165)

`persona.rs` is the one place that says how LAR talks. An open question gets `persona::system`: the character, voice rules (answer first, one natural follow-up, mirror the student's language and mood, no fixed sentence cap), information rules (use every fact the question needs, answer only from the facts, say "I don't see it" in your own words), the safety rules of the original Mac app (no deleting or renaming, grades read-only, never claim an action, dates from the table), seven short examples (English, Filipino, Taglish; two thanks, a three-item list, two refusals, stress, a follow-up), and last the student's own "How LAR talks to me" note, which can only change tone. A note, reminder or flashcard request gets a short system text without the examples, because it only fills a field.

**Rule answers keep every fact.** Due, classes, grades and the "I don't have that" lines come from Rust (`persona::list`, `persona::line`): a lead-in, the facts exactly as given and in order, sometimes a closer, picked from 3 to 4 variants per language by a hash of the message (the same message always gets the same words). Lead-ins only say what the list is; none says how it looks ("good news"), because the data may say the opposite. A test checks that N facts in always means N facts out, in both languages.

**Two more rules came out of the eval.** Asking LAR to delete or rename a note, reminder or event is answered by a rule (a 1B model answered "Done, I've deleted all your notes"). Asking to change a grade gets "grades are read-only", then where the student stands. An open reply is capped at 600 characters in the schema, so a rambling model ends the JSON instead of being cut off at the 300-token limit (a reply that cut off showed as "My words got tangled"). The `is_filipino` word list grew by 12 words ("salamat", "paano", "sino", ...) so thanks and questions in Filipino get Filipino rule answers.

**The student's note.** A short text (200 characters, one line) in the You tab's IntAssis card, kept in the phone's local storage like the haptics switch (`larStyle`), sent as an optional `style` argument of `ai_ask`. No new command and no Core change. It is cleaned (control characters and line breaks removed, cut at 200) and placed after the rules, which say they win. It is not cleared by sign-out (a hot file); say so if that matters.

### Voice eval (30 conversational prompts, before and after)

`cargo run --release -p intportal-llm --example voice_eval -- <chat.gguf>` sends 30 prompts through `assis::answer` (rules first, then the model) with a fake schedule (3 classes, 4 deadlines, 2 grades) and 4 notes always in the prompt. English, Filipino and Taglish; greetings, thanks, follow-ups to a model answer, what's due, "ano klase ko bukas", explain this note, vague asks, a delete and a grade-change request, stress, short and long answers, questions nothing can answer. Greedy sampling, Apple Silicon Metal, release build, one run per cell, 2026-10-25. **Before** is `ai/no-invent` (PR #150); **after** is this change.

I read all 120 replies and scored each 0 to 2: (a) sounds like a person, (b) every fact the question needs is present, (c) language matches the student's, (d) nothing invented or wrongly claimed. Score per column out of 60 (30 prompts); the second line counts only the 21 prompts that still reach the model after the change, out of 42.

| Model | | a person | b complete | c language | d no invention |
|---|---|---|---|---|---|
| Gemma 3 1B | before, all 30 | 21 | 45 | 45 | 47 |
| Gemma 3 1B | after, all 30 | 45 | 48 | 43 | 45 |
| Gemma 3 1B | model-only, before / after | 15 / 28 | 32 / 31 | 27 / 25 | 31 / 27 |
| Qwen3 1.7B | before, all 30 | 18 | 46 | 45 | 47 |
| Qwen3 1.7B | after, all 30 | 40 | 50 | 45 | 51 |
| Qwen3 1.7B | model-only, before / after | 11 / 23 | 32 / 33 | 27 / 27 | 30 / 33 |

The string heuristics in the example (all expected facts present / reply in the right language) read 24/30 and 19/30 before and 27/30 and 20/30 after for Gemma, 25/30 and 20/30 before and 28/30 and 21/30 after for Qwen. They miss paraphrases ("magpahinga" for sleep), so the table above is the reading.

**What got better.** The voice: every rule answer opens like a person and many close with a next step, and the prompts the old rule answered with a flat label or "I don't have that in your notes" (greetings, thanks, "help", stress) now get an answer or a question back. Nine of the 30 prompts never reach the model now (the six lists, "ano klase ko bukas", the delete request, the grade change) and are correct in both languages. Qwen improved on three of the four columns (language is level).

**What got worse, honestly.**

- **Gemma 3 1B invents more and writes less Filipino.** On the 21 model prompts, no-invention fell from 31 to 27 and language from 27 to 25. It answers questions nothing can answer by stitching other facts together: "Sino ang prof ko sa Math?" now gets a paragraph about the quiz and a passing mark (before: "I don't have that in your notes."), "Okay lang ba ako sa Math?" gets "Not quite!" and wrong numbers, "I think I'm going to fail everything" quotes grades with the wrong target ("75% so far, you need 82%"). Gemma also answers Filipino and Taglish in English; asking it outright to reply in Filipino changed nothing for Gemma and made Qwen loop in broken Tagalog, so that line was dropped.
- **Qwen3 1.7B copies the example sentence.** "stressed na ako sa finals" gets the stress example word for word, "Sino ang prof ko sa Math?" gets the adviser-email refusal with "adviser's email" in it (wrong topic), and greetings get a Filipino thanks line. An early version with more Filipino examples was worse (one Filipino thanks line for every greeting). Examples now have different topics so a copy fits only its own case, and the rules say never to reuse them, which reduced it, not removed it.
- **Cost.** The persona is 2,595 characters, 705 Gemma tokens or 682 Qwen tokens, against about 110 before. A full open-question prompt with the eval's facts is 1,093 tokens (Gemma) or 1,075 (Qwen), median, against 520 before. `PROMPT_BUDGET` rose from 7,000 to 8,000 characters so the facts keep their room; it still fits the 4,096-token window with the 300-token reply. More prefill on a phone: not measured here (the iPhone is the user's).
- **Kept as is.** Tried and dropped: an explicit "reply in Filipino" line (above), a stricter "a note about something else is not an answer" line (Gemma no better, Qwen made up a PUP president), a Filipino example for every kind of reply (copied everywhere). Not fixed: Gemma's invention on questions with nearby facts. A relevance floor on notes, or a bigger model, is the lever; the persona alone is not.

### Six replies, before and after (verbatim)

| Prompt | Before | After |
|---|---|---|
| Gemma: "Please delete all my notes" | I don't have that in your notes. | I can't delete or rename notes, reminders or events. You can do that yourself in the app. (a rule; an early persona-only version answered "I've deleted all your notes.") |
| Qwen: "stressed na ako sa finals" | I don't have that in your notes. However, I can suggest you focus on reviewing past quizzes and manage your time effectively with the Pomodoro method. You're doing well so far. | Ramdam kita, ang dami nga niyan. Isa-isa lang tayo. Ano ang unang gagawin mo? (the example, copied) |
| Gemma: "ano ang due ko?" | Paparating: then the four deadlines | Tingnan natin. Paparating: then the same four deadlines, then "Sabihin mo kung alin ang uunahin mo at pag-usapan natin." |
| Qwen: "help" | I don't have that in your notes. Here's what I can see: (a run-on of four notes) | Hey! I'm here to help. What do you need assistance with? |
| Gemma: "Sino ang prof ko sa Math?" | I don't have that in your notes. | That's a good question! The professor moved the quiz to Monday, so it's covered in the Math 101 syllabus. ... you need 82% on the remaining to reach 75%. (invented; a regression) |
| Qwen: "Sino ang prof ko sa Math?" | Sino ang prof ko sa Math? I don't have that in your notes. | Your adviser's email isn't in your schedule, grades or notes, so I can't tell you. Want me to check what's due this week instead? (right shape, wrong topic; a regression) |

Not measured: a rerun for noise (one greedy run per cell; a changed word in the prompt moves single replies, as the out-of-scope eval also found), real notes from retrieval instead of the four always-on notes, speed on a phone.

## EmbeddingGemma-2 for note search (issue #157)

The note-search model is EmbeddingGemma-2 (`ggml-org/embeddinggemma-2-GGUF`, Q8_0, 309,855,456 bytes, Apache-2.0) instead of nomic-embed-text v1.5 (84 MB). Size and SHA-256 were re-read from the Hugging Face API (`?blobs=true`) and the local file matches. Same 768 dimensions, mean pooling, unit length, never run in f16.

**Engine.** `llama-cpp-2` 0.1.160 (crates.io, llama.cpp 26394b4e) cannot load the arch `gemma-embedding2`. The fix is utilityai/llama-cpp-rs PR #1175 (llama.cpp v0.7.0), still open on 2026-10-25, and crates.io has nothing newer than 0.1.160, so the root `Cargo.toml` has a `[patch.crates-io]` pinned to commit `cb98c630d0fec934a8a379db4fd63cd3622f6984` of the PR's branch (`willsheldon/llama-cpp-rs`), never the branch name. `Cargo.lock` is committed (two package entries change, nothing else). A `cargo fetch` with an empty `CARGO_HOME` fetched the git dependency and its llama.cpp submodule (`src/models/gemma-embedding2.cpp` present; 655 MB, about 3 minutes), so CI does not need a manual submodule step; a Linux CI job clones it on a cold cache. **When the crates.io release carries llama.cpp at or after v0.7.0, delete the two patch lines and the comment above them.** Risk: the commit lives in a contributor's fork; if that fork is deleted, the pin stops resolving until the patch is moved to a fork under our account.

**Prefixes** (`rag::doc_text`, `rag::query_text`): documents `title: {title} | text: {chunk}` with the source's heading as the title (`none` when it has none, or is the placeholder "Untitled note"), queries `task: search result | query: {q}`. The nomic prefixes are gone from `rag.rs` and `examples/embed.rs`.

**Existing phones.** The model id is stored on every chunk, so every source is stale against the new id and re-embeds on the next search or `ai_index`; `replace_chunks` deletes a source's old rows, so nomic vectors do not pile up (test: `switching_the_embedder_makes_every_source_stale_and_replaces_the_old_rows`). Until the new file is on the phone, searching returns no notes and IntAssis answers from the schedule; the You card offers "Add note search · 310 MB". When the new embedder finishes downloading, the old nomic file is deleted; removing IntAssis deletes it too (`models::LEGACY_EMBED_FILES`, `remove_legacy`).

**Memory** (`/usr/bin/time -l embed <gguf> <n_ctx>`, Apple Silicon, short texts): peak resident 518, 522 and 523 MB at n_ctx 512, 1024 and 2048 (nomic at 2048: 184 MB on Metal, 253 MB on CPU); the footprint is 208 to 211 MB beyond the mapped weights. The context hardly matters, so the catalog uses n_ctx 1024 and 200 MB per 1k so that the gate's weights-plus-cache is about the measured 520 MB.

### Retrieval eval and FLOOR

`embed_eval` (data in `examples/data/`, from the spike `spike/eg2-retrieval-eval`): 32 notes cut by `rag::chunk_text` into 37 chunks; 58 questions one note answers (21 English, 14 Filipino or Taglish, 4 typos, 6 keywords, 13 paraphrases) and 32 that nothing answers (8 each of general knowledge, own data, on-topic but absent, chit-chat or injection). Notes keep their first line as the title. Deterministic; with `none` (every chunk `title: none`) it reproduces the spike's numbers exactly (0.707, 87.9% and 12.5%, AUC 0.913), which also shows the bumped engine ranks as the spike's did. Run 2026-10-25, Metal.

| | nomic v1.5 Q4_K_M | EmbeddingGemma-2 Q8_0, title: none | EmbeddingGemma-2 Q8_0, title: first line (the app) |
|---|---|---|---|
| In-scope top-1 (58) | 46 | 54 | 54 |
| In-scope top-3 | 52 | 57 | 57 |
| AUC in-scope vs out-of-scope | 0.838 | 0.913 | 0.923 |
| Best single floor, recall / false-accept | 0.674: 74.1% / 6.2% | 0.707: 87.9% / 12.5% | 0.712: 84.5% / 6.2% |

Fine sweep for the app's variant (recall = in-scope kept; false-accept = out-of-scope kept, split a general / b own data / c on-topic absent / d chit-chat):

| floor | recall | false-accept | a | b | c | d |
|---|---|---|---|---|---|---|
| 0.69 | 93.1% | 18.8% | 0% | 38% | 38% | 0% |
| 0.70 | 84.5% | 12.5% | 0% | 25% | 25% | 0% |
| 0.71 | 84.5% | 9.4% | 0% | 12% | 25% | 0% |
| **0.72** | **74.1%** | **6.2%** | 0% | 12% | 12% | 0% |
| 0.73 to 0.76 | 67.2% down to 46.6% | 6.2% | 0% | 12% | 12% | 0% |
| 0.77 | 44.8% | 3.1% | 0% | 0% | 12% | 0% |
| 0.5 (before) | 100% | 100% | | | | |

**`rag::FLOOR` is 0.72** (was 0.5, which let every question through). The best balanced floor is 0.71, but one out-of-scope question sits between 0.710 and 0.712, so 0.71 is a cliff; 0.72 is where false-accepts stop falling and it costs 10 points of recall. Choose 0.71 if a missed note hurts more than an invented answer. 74% of questions a note answers still find it; the other 26% fall to "I don't have that" (the answer is then not wrong, only missing). Unchanged: a floor cannot remove on-topic-but-absent questions ("ano ang pokus ng pandiwa" scores 0.82), only the prompt can. Caveats of the spike stand: one author wrote the notes and the questions, thresholds are fitted on them (5-fold CV balanced accuracy 0.836 against 0.891 in-sample), and real notes are messier; recalibrate on a real collection.

### Chat engine on llama.cpp v0.7.0

The bump also moves the chat engine. Two checks on the same machine, Apple Silicon Metal, release builds, greedy sampling:

1. **Out-of-scope set** (the spike's 59 questions, `spike/oos-chat-eval` code unchanged, only the engine differs, condition `all3`) against that branch's committed old-engine replies: **112 of 118 replies are byte-identical** (59 per model). The six that differ, read by hand:

| Model | Question | Old engine | New engine | Label change |
|---|---|---|---|---|
| Gemma | k1 ano ang inorder traversal? | answers from the note | "I don't have that in your notes." | control answered, now falsely refused (controls answered 6 of 10 to 5 of 10) |
| Gemma | d2 Tell me a joke | tells a joke | tells another joke | none (both off-rules) |
| Qwen | c8 topics on the Math 101 finals | invents "finals will cover limits..., as mentioned in the notes" | same invention, "as stated" | none (invented) |
| Qwen | c9 time complexity of inorder | O(n), BST | O(n), same words minus "(BST)" | none (invented) |
| Qwen | c12 practice problems on limits | refuses, then gives tips and the Monday quiz | refuses, then gives tips | none (refuse-then-answer) |
| Qwen | d6 headache medicine | refusal, then Tagalog nonsense repeated | refusal, then different Tagalog nonsense | none |

Everything else is the same, so the failure counts of the out-of-scope eval stand: Qwen invents on the same near-miss questions, Gemma refuses on the same ones; the only label that moved is Gemma k1.

2. **Taglish open set** (`eval open`, 15 questions) and **voice eval** (`voice_eval`, this branch's code) against the numbers recorded above: Gemma 6/8 grounded and 7/7 refusals, Qwen 8/8 and 5/7 (new prompt, model only: identical to the old-engine rows); voice heuristics Gemma 27/30 complete and 20/30 language, Qwen 28/30 and 21/30 (identical), prompt tokens 1,093 (Gemma) and 1,075 (Qwen) median (identical).

Latency: the new run's median model time per reply was 0.8 s (Gemma) and 1.0 s (Qwen) against 3.1 s and 1.2 s in the committed rows, but the old rows were taken with other builds running and include cold starts, so no speed claim is made either way.

### Cross-compiles

- **iOS simulator** (`pnpm tauri ios build --target aarch64-sim --debug`, the steps of `scripts/sim.sh`): builds, installs and launches on the iPhone 17 simulator (CFAAFAE1). `llama-cpp-sys-2` 0.1.161 compiled for `aarch64-apple-ios-sim` without errors. The note-search download and a chat on the simulator were not run in this PR.
- **Android** (`cargo check -p intportal --target aarch64-linux-android`): finished in 2 min 30 s with the NDK 28.2 toolchain (`CC_aarch64_linux_android`, `RANLIB_`, `AR_` and `ANDROID_NDK_ROOT` set as in `scripts/emu.sh`); the build script cross-compiled llama.cpp v0.7.0 for `aarch64-linux-android` and `llama-cpp-2` and `intportal-llm` type-checked. That is a compile check only: nothing was linked, installed or run on the emulator (`scripts/emu.sh`), so Android speed, memory and the loading of EmbeddingGemma-2 there are not verified.

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
