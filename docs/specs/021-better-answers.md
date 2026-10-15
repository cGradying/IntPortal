# 021 Better answers: an opt-in second chat model

**Status:** draft, wording to confirm. Nothing here is built. The user approves the criteria in this PR; no build PR opens before that. Issue: #141.

## What changes for the student

On the You tab, under IntAssis, a second card offers "Better answers": a larger model (Qwen3 1.7B, about 1.1 GB) that reads their notes more reliably than the default (Gemma 3 1B, 0.8 GB). It is a choice, never a default. The student adds it with one tap, picks which model answers, and can remove it to get the space back. Everything still runs on the phone.

## Direction and references

- ADR 0003 (on-device, opt-in, models never bundled, RAM gate). An addendum for two chat models is proposed at the end of this file; the Head decides whether to write it.
- Spec 020 C4, C8, C9: one download with progress, errors in the student's language, Light preselected. This spec adds to them and changes none.
- `docs/ai.md`, open-question eval (2026-10-15, Mac, Metal): Qwen3 1.7B grounded 8/8 against Gemma's 7/8, median 1.7 s against 2.2 s, but it refused only 4/7 unsupported questions (Gemma 5/7) and answers English to Taglish questions. Those Mac numbers say nothing about a phone (C12).
- Catalog today: `qwen3-1.7b` is already in `crates/intportal-ai/src/models.rs` (1,107,409,472 bytes, KV 115 MB per 1k tokens, context 4096); `DEFAULT_CHAT` is `gemma3-1b`. The gate there checks one model alone.

## Keep

- Light is the default; the default chat model is Gemma 3 1B. Nothing downloads unless the student taps.
- One chat model in memory at a time, plus the note-search model, which stays loaded.
- The chat history, the confirm cards, "Why?", source chips, exact answers that skip the model.
- Nothing is written without the student's tap.

## Behaviour

- **C1.** When IntAssis is on, the You tab shows a "Better answers" card under the IntAssis card. Before it is installed the card shows its name, one sentence of what it is for, the download size as the catalog states it ("1.1 GB"), the line "Use Wi-Fi", and an "Add Better answers · 1.1 GB" button. When IntAssis is off the card is not shown.
- **C2.** The card never promises more than the eval showed: it says the model "reads your notes more closely" and "can still be wrong", and it says nothing about being smarter, faster or more accurate overall. The size comes from the catalog, not from a literal in the view.
- **C3.** The memory gate counts everything that would be resident once this model is chosen: the chat model's weights and KV cache, plus the note-search model's. It never counts the other chat model, because that one is unloaded first (C7). Over 60% of the memory the app may still use shows "It may be a tight fit on this phone; answers could be slow." and still offers the button. Over 90% shows "This phone doesn't have enough free memory for it right now. Close other apps and open this again." and no Add button. The same gate runs again at the moment of switching to it (C6), not only at download time.
- **C4.** Nothing downloads without a tap on "Add Better answers". Opening the card, choosing a model, installing IntAssis, relaunching, updating the app and reconnecting to Wi-Fi never start or resume a download. A half-finished download shows "Resume · {done} of {total}" and waits for a tap.
- **C5.** The download shows its own progress bar with percent and "{done} of {total}", can be paused, resumes where it stopped, and is checked against the pinned SHA-256 before the model counts as installed. A failed check deletes the file and shows the failure copy (C14). When it finishes the card says "Added" and does not switch the answering model by itself.
- **C6.** With both models installed, the card shows a two-option choice: "Light" (Gemma 3 1B) and "Better answers" (Qwen3 1.7B). Tapping the other option makes it the one that answers the next open question. The choice is remembered after the app closes. With only one chat model installed there is no choice to show and the default answers.
- **C7.** Only one chat model is loaded at any time. Switching unloads the old chat model before the new one loads; the note-search model is not unloaded or reloaded. After a switch, `ai_models` reports exactly one chat model with `loaded` true and the embedder still loaded. The first message after a switch shows "Waking up", like the first message after launch. If the new model fails to load, the choice goes back to the previous model and the failure copy shows (C14).
- **C8.** Switching keeps the conversation: the same turns are shown after the switch and after relaunch, and the next question sees the same history it would have. Switching does not run while LAR is writing: the choice is disabled until the reply finishes or the student taps Stop, and a tap meanwhile shows the busy sentence (C14).
- **C9.** "Remove Better answers" asks once ("Remove, free 1.1 GB" / "Keep"), then deletes the model file and any `.part` file, and the storage freed equals the file's size. If it was the answering model, Light answers from the next message, with no other change to the chat. Removing it never touches Gemma, the note-search model or the history. "Remove from this phone" on the IntAssis card (020 C4) also removes Better answers, and its confirm line adds up all the sizes it frees.
- **C10.** The default stays Light, meaning Gemma 3 1B: a fresh install, an update from a build without this spec, a student who never opens the card, and a student who removes Better answers all end up with Gemma answering. `models::DEFAULT_CHAT` does not change. The first-run "Light or With AI?" (020 C9) is unchanged and does not mention Better answers.
- **C11.** The reply is in the language the student wrote: English question, English reply; Filipino or Taglish question, Filipino or Taglish reply. Qwen3 answers English to Taglish unprompted, so the open-question prompt names the language when the question is Filipino (`intent::is_filipino`), as a short instruction in the system text (for example "Sagutin sa Filipino. Taglish ay okay."), and says nothing extra for English. The instruction is the same for both models, so the default's open-question eval must not get worse (C13). Exact answers and confirm cards already follow the language and are unchanged.
- **C12.** Speed is measured on real phones before the card ships, not on the Mac. Required, release build, Metal on iOS, a mid-range Android phone with 4 GB RAM for the Android build: (a) time from Send to the first word, warm and after "Waking up"; (b) tokens per second while writing; (c) wall time of a full reply, median and worst, across the 15 open questions; (d) peak resident memory with Qwen3 1.7B and the embedder loaded, and whether iOS ends the app when it goes to the background and returns; (e) whether five questions in a row make the phone slow down or hot. The Mac Metal run (median 1.7 s) and the iOS simulator (CPU only) do not count. The user runs the iPhone check through `scripts/phone.sh`. Proposed bar, to confirm: first word within 3 s warm, full reply median within 10 s, no kill after backgrounding. A phone that misses the bar sees the tight-fit line from C3; if the reference phones miss it, the feature does not ship and this spec goes back to draft.
- **C13.** Quality bar before shipping, same open-question eval as `docs/ai.md`, rerun with the C11 instruction and the relevance floor on both models: valid JSON 15/15 for both; Better answers grounded at least 8/8 and refusals at least as good as Gemma's 5/7, otherwise the card is held back; Gemma grounded stays at least 7/8. The result goes into `docs/ai.md`.
- **C14.** Every failure is one plain sentence in the student's language, from `assis::friendly`, with no codes. The table below lists the new ones; each gets a Filipino twin there and a test.
- **C15.** The card works with VoiceOver and TalkBack and with large text: see Accessibility.
- **C16.** Reduce Motion is honoured: see Motion.

## Copy

- Card: "Better answers". Line: "Reads your notes more closely. Slower than Light, and it can still be wrong." Size line: "One-time download · {size}. Use Wi-Fi. Works offline after that."
- Buttons: "Add Better answers · {size}", "Pause", "Resume · {done} of {total}", "Remove, free {size}", "Keep".
- Choice: "Light" with "Gemma 3 1B", and "Better answers" with "Qwen3 1.7B". Added: "Added. Pick it above to use it."
- Switched, shown once in the log as a small line: "Now answering with Better answers." / "Now answering with Light."
- Wording is a draft; the user confirms it in this PR.

## Data shape

- `ai_models()` rows gain `chosen: bool` (the model that answers). `ai_download(id)`, `ai_delete(id)` and `ai_load(id)` already take an id and are reused.
- New: `ai_choose(id)` stores the choice (one setting; Core reviews where it lives) and loads that model, applying the memory gate (C3) first. `assis::chat_model(chosen)` returns the catalog entry that `ai_ask` and `ai_note` use; unknown or missing falls back to `DEFAULT_CHAT`.
- `models::gate` takes the chat model and the embedder together (C3).
- `models::CATALOG` is unchanged. No new crate and no new dependency.

## Errors

| Case | English | Filipino |
|---|---|---|
| Not enough room to download | "There isn't enough space on this phone. Free up {size} and try again." | "Kulang ang espasyo ng phone. Maglaan ng {size} at subukan ulit." |
| Download stopped (offline, interrupted) | "The download stopped. Tap Resume to carry on." | "Huminto ang download. I-tap ang Resume para ituloy." |
| Checksum failed | "The download came out wrong, so I deleted it. Try again on Wi-Fi." | "Mali ang nakuha na file kaya binura ko. Subukan ulit sa Wi-Fi." |
| Too little memory to switch | "This phone doesn't have enough free memory for Better answers right now. Light is still answering." | "Kulang ang libreng memory para sa Better answers. Light pa rin ang sumasagot." |
| Switch while LAR is writing | "I'm still working on your last message. Give me a second." (existing busy sentence) | "Ginagawa ko pa ang huli mong mensahe. Sandali lang." |
| New model failed to load | "Better answers didn't start, so Light is answering." | "Hindi nagsimula ang Better answers kaya Light ang sumasagot." |
| Chosen model removed or missing | Light answers; the log line "Now answering with Light." | "Light na ang sumasagot." |

The existing sentences (not downloaded, too long, tangled JSON) are unchanged.

## Motion and Reduce Motion

The progress bar's width eases at 0.4 s today. Under Reduce Motion it jumps in whole steps without easing, and "Waking up" and the thinking dots are static (as in 020). Switching the choice has no animation beyond the selected state changing. Haptics follow the existing `buzz.tick()` use and are not required for any state.

## Accessibility

- The choice is a radio group: each option has a name, the model, its selected state and, when disabled during a reply, the reason ("Wait for LAR to finish").
- Progress is a progressbar with its value and the words "{done} of {total}". Warnings and failures are text, never only colour.
- Buttons are at least 44 px high and keep the card's `min(…rem, …px)` text sizes so large text does not clip; the card scrolls rather than truncating.
- A switch, a finished download and a failure are announced politely once, not on every progress tick.

## Out of scope

Choosing the model per question or automatically by phone; any third chat model; Qwen3 0.6B or Gemma 4 in the UI; a cloud model; changing which questions skip the model; changing the RAG relevance floor itself (only its use in the C13 rerun).

## Test map

| Criterion | Check |
|---|---|
| C1, C2 | screenshot of the card before install; `vitest` that the size shown equals the catalog size |
| C3 | `cargo test -p intportal-ai c3_gate_counts_chat_and_embedder…` at 4.0 GB (Ok), 2.5 GB (Warn), 1.8 GB (Refuse) for Qwen3 1.7B plus nomic; screenshots of both lines |
| C4 | `vitest` that no `ai_download` call happens on open, on choose, on relaunch or after an app update; relaunch with a `.part` file |
| C5 | `cargo test -p intportal-llm` resume and wrong-hash tests (exist for the default); screenshot of two bars at different times |
| C6, C8 | `vitest` choose and busy-disabled; relaunch on the simulator with both installed |
| C7 | `cargo test` on `AiState` with fake loaders: after a switch one chat slot is loaded and the embedder's is untouched; a failing load restores the choice |
| C9 | `cargo test` that delete removes the file and the `.part` and the next `ai_models` says not installed; screenshot of the confirm line |
| C10 | `cargo test -p intportal-ai default_chat_is_gemma…`; fresh install and upgrade on the simulator |
| C11 | `cargo test -p intportal-ai c11_filipino_question_names_the_language…` (instruction present for a Taglish message, absent for English); Taglish rerun in C13 |
| C12 | phone numbers pasted into `docs/ai.md` and the PR, by the user on the iPhone and by AI on the emulator; no CI check |
| C13 | `cargo run --release -p intportal-llm --example eval -- <chat.gguf> open` on both models; table added to `docs/ai.md` |
| C14 | `cargo test -p intportal-ai friendly…` for each row in both languages |
| C15 | VoiceOver on the iPhone 17 simulator, TalkBack on the emulator, screenshot at the largest text size |
| C16 | screenshot with Reduce Motion on; `vitest` that the bar's transition is `none` under `prefers-reduced-motion` |

## ADR 0003 addendum (proposal for the Head)

> **Addendum, two chat models.** IntAssis may hold two chat models on the phone, the default (Gemma 3 1B) and one opt-in larger model (Qwen3 1.7B, "Better answers"), chosen by the student and remembered. Only one chat model is ever loaded; the note-search model stays loaded beside it, and the RAM gate counts the chosen chat model plus the note-search model, so the storage consequence becomes up to about 2.0 GB with both chat models, and a Storage view lists each one with its own Remove. The default does not change, nothing downloads without a tap, and the "no AI command writes" and structured-output rules apply to both models identically. A larger model ships only if release-build speed and memory on a real phone, and the open-question eval, meet the bar in spec 021 (C12, C13); otherwise the catalog entry stays unused.

## Open questions

1. For the user: should "Better answers" be the name? Alternatives: "Smarter LAR", "Mas mahusay na sagot". Is "Light" a clear name for the model that answers by default, given Light already means "no AI" at first run? The spec reuses it for Gemma in the choice; a different word (such as "Fast") avoids the clash.
2. For the user: C12 thresholds (3 s to first word, 10 s median full reply, no kill in the background). Too strict or too loose for the phones students have? Which phones count as reference devices?
3. For the Head: may a student install Better answers without the default? This spec says no (the card needs IntAssis on, so Gemma and the note-search model are present). The alternative saves 0.8 GB but needs a different first-run path.
4. For the Head: wording for "Wi-Fi". The app cannot reliably tell Wi-Fi from mobile data on both platforms, so C1 is a hint, not a block. Is a hint enough, or should the plugin report the connection?
5. For the Head and Core: where the choice is stored (a store setting, or a file beside the models) and whether it clears on sign-out and wipe like the chat turns. This spec assumes it survives sign-out because it describes the phone, not the student.
6. For the Head: C13 holds the card back if Qwen refuses fewer unsupported questions than Gemma. Is a lower refusal rate acceptable if the card copy says so, or is holding it back right?
7. For the Head: should the app offer a one-time nudge to try Better answers when the student's phone has plenty of memory? This spec says no; it stays a quiet card.
