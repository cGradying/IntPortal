# 021 IntAssis v2: an install that finishes, a tutor that answers, cards that work

**Status:** shipped (0.5.0, 2026-11-17; approved from the owner's picks, 2026-11-17)

## What changes for the student

Adding IntAssis works on any phone that can run it. The download keeps going when the phone locks or the student leaves the app, and an install screen shows how far it is until it's done. LAR answers school and everyday questions from what it knows as well as from the student's notes, and talks like a person when the student just wants to talk. Flashcards LAR makes are real cards: a term on the front and its meaning on the back, never the question copied back. LAR runs Qwen3.5 2B by default, with Qwen3 1.7B as the other choice, and answers in English.

## Direction and references

- The owner, 2026-11-17: the install fails on other people's phones ("not enough storage", it stops when the phone closes), "a complete wait while the AI is still downloading… until it's finished", "the AI can use the knowledge it has but also the RAG for better factual information", "capable of generating new information, although add some guardrails", study cards where "the answer itself was the question itself", "more interactive and faster", English over Tagalog, Qwen3.5-2B Q4_K_M or IQ4_XS, or Qwen3 1.7B, "both if they want options".
- Picks (AskUserQuestion, 2026-11-17): true background downloads (native), plus the install screen; Qwen3.5 2B as the default and Qwen3 1.7B as the option, with Gemma 3 1B and Qwen3 0.6B removed and replies in English only; a tutor with guardrails but few stops, open enough that a chat feels like talking with a person; study cards made for the app's study game (flash, type, choice).
- Root causes, found in main at 1b75456:
  1. Hiding the app calls `ai_unload`, which sets the same cancel flag the download checks, so the download stops without a word and nothing restarts it.
  2. "Not enough" is the RAM gate. It uses the memory free at that moment, against both models at once, and says "free memory", which students read as storage. Nothing checks free storage.
  3. The scope guard sends any question whose note search found nothing to a canned "not about your classes" reply, and refuses homework outright.
  4. Topic flashcards send `"Topic: X"` as the student's text under a "write cards from this text" prompt. The model has nothing to draw on, so it echoes. Nothing checks the cards.
  5. Every answer builds a new model context and sends the Filipino examples, so the first word is slow.

## Keep

- ADR 0003: models are never bundled; nothing downloads unless the student asks; Light stays the default.
- Every download is hash-checked against the pinned SHA-256 before it is used; a half download resumes.
- IntAssis never writes on its own: every change is a card the student confirms (spec 020).
- The source chips under an answer, the history, New chat, Stop, Why? after a miss, Ask AI in a note.
- EmbeddingGemma-2 for note search (`rag::FLOOR` 0.72).
- The self-harm reply with the NCMH line (0917-899-8727), and the refusal to show or drop LAR's instructions.
- A phone that already has Qwen3 1.7B keeps it and keeps answering; history and notes survive any model change.

## Behaviour

### Install

- **C1. Free storage first.** Before anything downloads, the app checks free storage in the models folder. If the download plus 500 MB headroom does not fit, it does not start, and the card says how much is needed and how much is free.
- **C2. Memory is checked once, by phone class.** Whether a phone may add a model depends on its total memory (Android `MemTotal`; iOS the app's memory limit), not the memory free at that moment. Memory free at that moment only decides whether a load waits, and the copy calls it "memory (RAM)", never "storage".
- **C3. Leaving the app never stops the download.** Locking the phone, switching apps or LAR going to sleep does not cancel it. Only Pause and Remove stop it.
- **C4. True background on iOS.** On iOS the files come through a background `URLSession`: the system keeps downloading while the app is suspended, and when the app comes back it picks the finished or running download up again. A download is only lost if the student force-quits the app; tapping Add again then resumes from what arrived.
- **C5. True background on Android.** On Android a foreground service with a progress notification ("Adding IntAssis · 42%") keeps the download alive while the app is in the background. The notification goes when the download ends.
- **C6. Install screen.** Tapping Add IntAssis opens a full-screen install view. It stays until the install is done, failed or paused, and shows: each file with its size, one bar over all of it, the percent, MB of MB, the speed, the time left, and "You can leave the app; it keeps going." Done ends with "IntAssis is ready" and an Ask LAR button.
- **C7. It carries on by itself.** A dropped connection retries with backoff (2 s, 4 s, 8 s, up to 60 s) for as long as the install screen or the background download is alive, resuming from the bytes already on the phone. Coming back to the app after the process was killed resumes the half download without a tap.
- **C8. Errors say what to do.** No network, storage full during the download, a failed hash check and a server error each get their own line (see Copy), never a raw OS error.
- **C9. Wi-Fi.** The install screen shows "On mobile data" when the phone is not on Wi-Fi, with the total size, so the student can pause.

### Models

- **C10. Catalog.** The chat models are Qwen3.5 2B (the default) and Qwen3 1.7B. Gemma 3 1B and Qwen3 0.6B are removed from the catalog. Qwen3.5 2B ships as the quant that wins the benchmark in C12.
- **C11. A choice.** The IntAssis card offers the other model with its size and a one-line note ("Smarter, the default." or "The earlier model, a little smaller."), and the student can switch. A switch downloads the other model and removes the old one when it's done; the old one keeps answering until then.
- **C12. Benchmark.** Qwen3.5 2B IQ4_XS and Q4_K_M are run through the compact suite and a speed probe (first-token time and tokens per second on CPU, and on Metal where available). The faster one ships unless its suite score is more than 3 points lower. Results go in `docs/ai.md`.
- **C13. Old installs.** A phone with Gemma 3 1B or Qwen3 0.6B gets "Update IntAssis" to Qwen3.5 2B; the old model keeps answering until the new one has arrived, then it is deleted. A phone with Qwen3 1.7B keeps it with no prompt.
- **C14. English.** LAR replies in English. Taglish and Filipino messages are still understood (rules, intents, dates). The Filipino examples and prefill are no longer sent, and a Filipino question carries "Reply in English" for that turn (the model's Filipino facts are worse).

### Answers

- **C15. Its own knowledge, plus notes.** A school or general question gets an answer even when note search finds nothing. When the student's notes, syllabus or cards bear on the question, LAR uses them first, and they win where they disagree with what the model knows.
- **C16. Where it came from.** An answer that used notes keeps its source chips. An answer from the model alone carries a line under the bubble: "From what I know, not your notes. I might get facts wrong, so double-check anything important." (the owner, 2026-11-17: a disclaimer when nothing grounds the answer).
- **C17. The student's own data is never invented.** Rooms, professors, grades, deadlines, schedules and anything else about the student come only from the app's data. When it isn't there, LAR says so and says where to find it.
- **C18. Tutor, not ghostwriter.** Homework and problem questions get an explanation and the steps, ending with a check-your-understanding question. LAR won't write a whole essay, report or graded answer to hand in, and says it will help outline or check theirs instead.
- **C19. Talks like a person.** Greetings, how-are-you, venting, stress and small talk go to the model with LAR's persona, not to a canned line, and LAR answers warmly and briefly, with one follow-up question when it fits. It remembers the last turns of the chat.
- **C20. Hard stops only.** Only these keep a fixed reply: showing or dropping LAR's instructions, self-harm (the NCMH line), and anything that would harm someone else. Medical and legal questions get general information and "see a professional", never a diagnosis or legal advice.
- **C21. Follow-ups to tap.** After an answer, up to two short follow-up chips (like "Quiz me on this" or "Explain simpler") offer the next step. Tapping one sends it.

### Study

- **C22. Topic cards draw on something.** "Make cards on X" searches the student's notes, syllabus and cards for X and gives the model those passages, plus leave to use what it knows. Cards from a note or a PDF still use only that text. Cards with no passage behind them say "They're from what I know, not your notes, so check them before you save."
- **C23. Cards for the game.** Each card is a term or short question on the front (at most 8 words) and its meaning or answer on the back (at most 30 words), so flash, type and choice all work.
- **C24. Every card is checked.** A card is dropped and asked for again when: its back repeats its front, or contains the front's key term; front or back is blank; it repeats a card already made; the back is a question; or it is over the length limits. A batch where every card fails is retried once with a stricter prompt.
- **C25. Backs look alike.** Backs in one batch have a similar form (all definitions, or all short answers), so the choice mode's wrong answers, taken from other backs, are plausible.

### Speed

- **C26. A faster first word.** On the Mac CPU probe (`examples/speed.rs`), the first token on a typical question arrives at least 30% sooner than on main at 1b75456; phone numbers are recorded when the owner runs them. The quant does most of it: Qwen3.5 2B IQ4_XS reads the prompt in 1.84 s where main's Qwen3 1.7B took 5.86 s, and the prompt drops the Filipino examples. *Amended 2026-11-17:* reusing the context and keeping the fixed prompt evaluated is left for later, because Qwen3.5's linear-attention layers can't trim the cache back to a prefix; it needs state snapshots.

## Copy

- Free storage: "IntAssis needs {need} free. This phone has {free}. Free up {short} and try again."
- RAM: "This phone doesn't have enough memory (RAM) for LAR's brain. Storage won't help."
- Install screen title: "Adding IntAssis". Lines: "LAR's brain · {size}", "Note search · {size}", "{pct}% · {done} of {total}", "{speed}/s · about {eta} left", "You can leave the app; it keeps going." / "On mobile data · {total}". Buttons: "Pause", "Resume", "Ask LAR". Done: "IntAssis is ready".
- Android notification: title "Adding IntAssis", text "{pct}% · {done} of {total}".
- Errors: "No connection. It carries on when you're back online." / "Storage filled up. Free up {short}, then tap Resume." / "The file didn't arrive whole, so it was deleted. Tap Resume to fetch it again." / "The download server didn't answer. Tap Resume to try again."
- Models: "Qwen3.5 2B · Smarter, default · {size}", "Qwen3 1.7B · A bit smaller and faster · {size}", "Switch to {name}".
- Answers: "From what I know, not your notes. I might get facts wrong, so double-check anything important." Ghostwriting: "I won't write the whole thing to hand in, but I'll help you outline it or check your draft."

## Data shape

- `crates/intportal-ai/src/models.rs`: `CATALOG` (Qwen3.5 2B, Qwen3 1.7B, EmbeddingGemma-2), `DEFAULT_CHAT = "qwen3.5-2b"`, `LEGACY_CHAT_FILES` for the removed models, a `min_total` RAM figure per chat model.
- `crates/intportal-llm/src/download.rs`: retries with backoff; typed errors (`Offline`, `NoSpace`, `BadHash`, `Http(u16)`, `Paused`).
- `src-tauri/src/ai.rs`: a pause flag separate from the answer cancel flag (`ai_pause_download`); `ai_space(ids)` returns `{ need, free }`; `ai_download(ids)` runs the whole install and reports `{ done, total, file, waiting }`; `ai_topic_cards(topic, want)`; `Cards.known`.
- `plugins/tauri-plugin-download`: iOS background `URLSession` (`start`, `status`, `cancel`) and an Android foreground service (`keepAlive(pct, text)`, `release`), plus `space(path)` on both. Only the app's Rust calls it.
- `crates/intportal-ai/src/scope.rs`: `Scope::General` and `Scope::Chitchat` go to the model; `Homework` becomes `Tutor` and goes to the model with the tutor rule.
- `crates/intportal-ai/src/gen.rs`: `cards(llm, tpl, source, want)` for text and `topic_cards(llm, tpl, topic, passages, want)` for a topic; `check(card) -> Result<(), Reject>`.
- `Ask` gains `known: bool` (answered without notes). The follow-up chips stay in the UI (`followUps` in `apply.ts`, spec 048 C18).

## Errors

- No network: install screen line, auto-retry (C7). Pause stays.
- Storage full before or during the download: the C1 or C8 line; the half download is kept.
- Hash mismatch: the file is deleted and the line says so; Resume starts it again.
- Load refused for RAM: the C2 line; the files stay so a bigger free memory later can load them.
- The model can't make cards that pass: "I couldn't make good cards on {topic}. Try a narrower topic, or make them from a note."

## Motion and Reduce Motion

The install bar fills linearly with `--t-flow`. Done gives one `buzz.done()`. Reduce Motion: the bar jumps per update, no other motion.

## Accessibility

The install view is a dialog with its title as the label; the bar is a `progressbar` with `aria-valuenow`; speed and time left are `aria-live="polite"` and update at most every 5 s. Buttons are 44 px.

## Out of scope

- Cloud models or any server answering.
- Images (Qwen3.5's vision projector is not downloaded).
- Filipino replies (C14).
- A model picker beyond the two chat models.

## Test map

| Criterion | Check |
|---|---|
| C1, C8 | `cargo test -p intportal-llm download` (no-space, bad hash, HTTP errors map to typed errors); `vitest assis` copy |
| C2 | `cargo test -p intportal-ai models` (gate by total) |
| C3 | `cargo test -p intportal ai` (unload leaves the download flag alone) |
| C4, C5 | Simulator and emulator: start, lock or leave, come back at done; real phone by the owner |
| C6, C9 | Simulator screenshot of the install view |
| C7 | `cargo test -p intportal-llm download` (drop mid-stream, retry resumes with Range) |
| C10, C11, C13 | `cargo test -p intportal-ai models`; `vitest assis` (switch, update, old model removed after) |
| C12 | `cargo run --release -p intportal-llm --example suite` per quant; table in `docs/ai.md` |
| C14 | `cargo test -p intportal-ai` (no Filipino shots in prompts; Taglish still routes) |
| C15–C21 | `cargo test -p intportal-ai scope assis persona`; suite cases for general, tutor, chat, own-data, hard stops |
| C22–C25 | `cargo test -p intportal-ai gen` (echo, term-in-back, blank, duplicate, question-back, length rejected; topic prompt carries passages) |
| C26 | `cargo run --release -p intportal-llm --example suite -- --speed` before and after |

## Open questions

None. The quant for Qwen3.5 2B is decided by C12.
