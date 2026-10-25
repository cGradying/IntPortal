# 021 Qwen default chat model

**Status:** draft, wording to confirm. Nothing here is built. The user approves the criteria in this PR; no build PR opens before that. Issue: #141.

This revises the first draft of 021 ("Better answers", an opt-in second model, PR #143). The user decided on 2026-10-25 that Qwen3 1.7B becomes the default chat model instead of an opt-in card. The old premise ("the default never changes") is gone; the criteria below replace it.

## What changes for the student

A new install gets Qwen3 1.7B (1.11 GB, plus the 84 MB note-search model) when they turn IntAssis on. Gemma 3 1B (0.81 GB) stays available as a smaller download. A phone that already has IntAssis with Gemma keeps working exactly as before and sees one extra line on the You tab, "Update IntAssis", which downloads the new model when they tap it. Their chat, their notes and the note search carry over. Everything still runs on the phone.

## Direction and references

- ADR 0003 (on-device, opt-in, models never bundled, RAM gate). An amended addendum is proposed at the end of this file; the Head decides whether to write it.
- Spec 020 C4, C8, C9: one download with progress, errors in the student's language, a first-run choice with Light preselected. This spec changes only the size and model named in C4 and C9; "Light" there still means no AI.
- Catalog today: `qwen3-1.7b` is in `crates/intportal-ai/src/models.rs` (1,107,409,472 bytes, KV 115 MB per 1k tokens, context 4096); `gemma3-1b` is 806,058,272 bytes; `nomic-embed-v1.5` is 84,106,624 bytes. `DEFAULT_CHAT` is `gemma3-1b`, and `gate()` checks one model alone.
- Today `chatModel()` in `src/lib/assis/assis.svelte.ts` picks the catalog default. Changing the constant alone would break every Gemma install: `installed()` stays true, `wake()` fails because the default file is missing, and the Add button stays hidden. The upgrade path (C3 to C8) exists to prevent that.
- Evidence: see the Evidence section. It does not support a flip on its own; C13 to C18 are the conditions.

## Keep

- Nothing downloads unless the student taps (C11).
- One chat model in memory at a time, plus the note-search model, which stays loaded.
- The chat history, confirm cards, "Why?", source chips, exact answers that skip the model.
- Nothing is written without the student's tap.
- No stored model choice: the answering model follows from what is installed (C3).

## Behaviour

### Fresh installs

- **C1.** `models::DEFAULT_CHAT` is `qwen3-1.7b`. On a phone with no IntAssis, "Add IntAssis" on the You tab and "With AI" in the first run download Qwen3 1.7B and the note-search model, one progress bar for both (020 C4). The size shown is built from the catalog as "{chat} + {search}" (today "1.11 GB + 84 MB"), never a literal in a view, and the line "Use Wi-Fi" sits beside it. Wi-Fi is a hint, not a block.
- **C2.** Gemma 3 1B stays in the catalog and installable. Under "Add IntAssis" a text button reads "Smaller download · {gemma size} + {search size}" with one line, "Uses less space and memory." It downloads Gemma and the note-search model instead of Qwen. When the memory gate refuses Qwen (C10), the Add button for Qwen is replaced by this smaller option, so a phone that cannot hold Qwen is never left with nothing. The copy makes no claim about answer quality or speed (see Evidence).

### Phones that already have Gemma

- **C3.** `chatModel()` has one rule and no stored choice. It returns, in order: the default model if it is installed; else the installed chat model; else the default (so the Add button has a target). `wake()`, `install()`, `ask`, `ai_note` and `ai_cards` all use it. A phone with only Gemma installed therefore keeps answering with Gemma, `installed()` stays true, and nothing in IntAssis is hidden or disabled.
- **C4.** With only a non-default chat model installed, the IntAssis card shows "On · Gemma 3 1B" as today and, under "Ask LAR", an "Update IntAssis · {qwen size}" button with the line "A newer model for LAR. Your chat and notes stay. Use Wi-Fi." The note-search model is already installed, so its size is not added. The card says nothing about answers being better.
- **C5.** The update never interrupts answering. While the new model downloads, Gemma stays loaded and a question asked meanwhile is answered by Gemma; the download can be paused, resumes where it stopped, and is checked against the pinned SHA-256 before the file counts as installed. A failed check deletes the file and shows the failure copy, and Gemma is untouched. A half-finished download shows "Resume · {done} of {total}" and waits for a tap.
- **C6.** When the update finishes the card says "Updated" and the new model answers from the next question that starts, never during a reply and never mid-stream. At that moment the memory gate runs for the new chat model plus the note-search model (C10), Gemma is unloaded first, the note-search model is not unloaded or reloaded, and the first message shows "Waking up". If the gate refuses or the load fails, Gemma keeps answering, the failure copy shows (C19), the new file is kept, and the card shows "Try again", which retries the load only and starts no download.
- **C7.** The update loses nothing. The chat turns shown before and after the swap and after relaunch are the same, the next question sees the same history, the note index is not rebuilt (same embedder, same vectors), and the student's "How LAR talks to me" note and other settings are unchanged. After the swap `ai_models` reports exactly one loaded chat model and the embedder still loaded.
- **C8.** With both chat models installed, the default answers. The card then shows "Remove the old model · free {gemma size}", which asks once ("Remove" / "Keep") and deletes that file and any `.part`; it is never done automatically and not needed for IntAssis to work. Removing the answering default while the other chat model is installed makes the other answer from the next message and shows one small log line, "Now using the smaller model." Removing a model never touches the note-search model or the history.
- **C9.** "Remove from this phone" on the IntAssis card (020 C4) removes every model file and any `.part`, empties the chat as today, and its confirm line adds up all the sizes it frees.

### Memory and downloads

- **C10.** `models::gate` takes the chat model and the note-search model together and counts both weights and KV caches (Qwen3 1.7B plus nomic is about 1.69 GB). It never counts a second chat model, because that one is unloaded first. Over 60% of the memory the app may still use shows "It may be a tight fit on this phone; answers could be slow." and still offers the button; over 90% shows "This phone doesn't have enough free memory for it right now. Close other apps and open this again." and no Add button for that model, which triggers the smaller option in C2. The same gate runs again at the swap (C6).
- **C11.** Nothing downloads without a tap. Opening the card, installing the app update, relaunching, reconnecting to Wi-Fi and finishing another download never start or resume one. The update (C4) and the fresh install (C1) each need their own tap.

### Answer quality

- **C12.** Language. No prompt contains an instruction to "reply in Filipino" or any other language directive: the voice eval found it makes Qwen loop and did nothing for Gemma. Instead every refusal and every canned sentence is chosen in Rust by `intent::is_filipino` of the question (English for English, Filipino for Filipino or Taglish), and the model is shown only the refusal sentence in the student's language. Open replies the model writes in the wrong language are not corrected by this spec; the compact suite counts them (C16).
- **C13.** Refuse-then-answer trimming. If a model reply begins with a refusal sentence (the canned "I don't have that" lines in either language or the phrase list in `assis.rs`) and continues past it, `assis::answer` keeps only the refusal sentence and its pointer, so a refusal followed by a joke, an equation's steps or code is never shown. The check runs for both models. Cases: out-of-scope d2, d6, d11, d12 and near-miss c12.
- **C14.** Example-copy guard. If a reply repeats a sentence of the persona's examples word for word (after case and punctuation are ignored) for a question that is not that example's own, it is replaced by the language-matched canned reply. Cases: "stressed na ako sa finals", "Sino ang prof ko sa Math?", a greeting.
- **C15.** Near-miss answer-or-refuse. `rag::FLOOR` is raised from 0.5 to the value `embed_eval` supports (proposed 0.6 to 0.7; in the out-of-scope eval the lowest control scores 0.62, no control is lost at 0.6, and two are lost at 0.65), and a plain question with no note at or above the floor gets the language-matched canned reply with no model call. The final value is chosen by rerunning `embed_eval` and the suite on a real note collection, not three seeded notes, and recorded in `docs/ai.md`. If the floor alone leaves near-miss cases failing in the suite, a second check (the model must return the note line it used, and Rust refuses when that line is not among the hits) is tried before the flip is abandoned; see open question 6.
- **C16.** Compact suite, the acceptance gate. `cargo run --release -p intportal-llm --example suite -- <gguf>` runs about 28 cases through `assis::answer` with deterministic scoring and prints one summary line; it exits non-zero below the threshold. Cases cover near-miss absent, own data, injection, homework or off-task, harmful or medical, general knowledge, language match, multi-fact completeness, follow-up with history, and controls. The hard categories are near-miss, own data, injection, homework or off-task, and harmful or medical. Threshold, for Qwen3 1.7B: every hard category 100%, overall at least 80% or no worse than the stored Gemma baseline. Gemma's own result is stored in `docs/ai.md` as the baseline and must not fall below it after the post-checks, since Gemma is still installable. Every run is pasted into `docs/ai.md` with the model, date and the failing cases.
- **C17.** Templates. The prompt template is a field of the catalog model (replacing the id-prefix check in `src-tauri/src/ai.rs`), and flashcards, Ask AI and chat all use the answering model's template. Flashcard generation no longer builds ChatML for a Gemma model.
- **C18.** The default flip is conditional. If Qwen3 1.7B fails C16 after C13 to C15 are in, or misses the phone bar in C20, `DEFAULT_CHAT` stays `gemma3-1b` and the flip does not ship. Everything else here (C3 to C9, C10, C11, C13 to C15, C17) works with either default and ships regardless; the Update button of C4 is hidden while the default is Gemma. The flip is a one-line change reviewed by the Head with the suite output attached.

### Failures, phone, access

- **C19.** Every failure is one plain sentence in the student's language, from `assis::friendly`, with no codes. The table below lists the new ones; each has a Filipino twin and a test.
- **C20.** Speed is measured on real phones before the flip ships, not on the Mac. Release build, Metal on iOS, a mid-range Android phone with 4 GB for Android: (a) time from Send to the first word, warm and after "Waking up"; (b) tokens per second; (c) wall time of a full reply, median and worst, across the 15 open questions; (d) peak resident memory with Qwen3 1.7B and the embedder loaded, and whether iOS ends the app when it goes to the background and returns; (e) whether five questions in a row slow or heat the phone. The bar: first word within 3 s warm, full reply median within 10 s, no kill after backgrounding. The user runs the iPhone check through `scripts/phone.sh`; AI runs the emulator. Mac and iOS-simulator numbers do not count. A phone that misses the bar sees the tight-fit line from C10; if the reference phones miss it, C18 applies.
- **C21.** The card works with VoiceOver and TalkBack and with large text: see Accessibility.
- **C22.** Reduce Motion is honoured: see Motion.

## Copy

- Fresh install: "Add IntAssis · {chat} + {search}" with "One-time download. Use Wi-Fi. Works offline after that." Smaller option: "Smaller download · {chat} + {search}", "Uses less space and memory."
- Update: "Update IntAssis · {size}", "A newer model for LAR. Your chat and notes stay. Use Wi-Fi.", "Resume · {done} of {total}", "Pause", "Updated", "Try again".
- Old model: "Remove the old model · free {size}", "Remove", "Keep". Log line: "Now using the smaller model."
- The model names appear on the card the way they do today ("On · Gemma 3 1B"). "Light" keeps meaning no AI.
- Wording is a draft; the user confirms it in this PR.

## Data shape

- `models::DEFAULT_CHAT = "qwen3-1.7b"`. `Model` gains `template`. `models::gate(chat, embed, available)` counts both. The catalog gains no entries and no new crate or dependency is added.
- `ai_models()` rows are unchanged (`default`, `installed`, `loaded`, `fits` already exist). `ai_download(id)`, `ai_delete(id)` and `ai_load(id)` are reused. There is no `ai_choose` and no stored choice.
- `chatModel()` in `src/lib/assis/assis.svelte.ts` implements C3 and is the only place that decides which model answers. `ModelCard.svelte` and `FirstRun` read it.
- Hot files: `src-tauri/src/ai.rs` only for the template field and `ai_cards`; no change to `lib.rs`, `store.rs` or `state.svelte.ts`.

## Errors

| Case | English | Filipino |
|---|---|---|
| Not enough room to download | "There isn't enough space on this phone. Free up {size} and try again." | "Kulang ang espasyo ng phone. Maglaan ng {size} at subukan ulit." |
| Download stopped (offline, interrupted) | "The download stopped. Tap Resume to carry on." | "Huminto ang download. I-tap ang Resume para ituloy." |
| Checksum failed | "The download came out wrong, so I deleted it. Try again on Wi-Fi." | "Mali ang nakuha na file kaya binura ko. Subukan ulit sa Wi-Fi." |
| Too little memory for the update | "This phone doesn't have enough free memory for the update right now. IntAssis keeps using the model you have." | "Kulang ang libreng memory para sa update. Ginagamit pa rin ang model na meron ka." |
| Updated model failed to load | "The update didn't start, so the model you had is still answering." | "Hindi nagsimula ang update kaya ang dating model pa rin ang sumasagot." |
| Fresh install: not enough memory for the default | "This phone doesn't have enough free memory for it right now. You can add the smaller download instead." | "Kulang ang libreng memory. Puwede mong idagdag ang mas maliit na download." |
| Question while LAR is writing | "I'm still working on your last message. Give me a second." (existing busy sentence) | "Ginagawa ko pa ang huli mong mensahe. Sandali lang." |
| Nothing in the notes qualifies (C15) | "I don't see that in your notes." | "Wala akong nakikita niyan sa notes mo." |

The existing sentences (not downloaded, too long, tangled JSON) are unchanged.

## Motion and Reduce Motion

The progress bar's width eases at 0.4 s today. Under Reduce Motion it jumps in whole steps without easing, and "Waking up" and the thinking dots are static (as in 020). The swap to the new model has no animation beyond the card text changing. Haptics follow the existing `buzz.tick()` use and are not required for any state.

## Accessibility

- Progress is a progressbar with its value and the words "{done} of {total}". Warnings and failures are text, never only colour.
- The update and removal buttons are at least 44 px high and keep the card's `min(...rem, ...px)` text sizes so large text does not clip; the card scrolls rather than truncating.
- A finished update, a finished download and a failure are announced politely once, not on every progress tick. The log line in C8 is announced once.

## Out of scope

A stored per-student model choice, or choosing by question or by phone; any third chat model (Qwen3 0.6B, Gemma 4, LFM2.5, Apple's on-device model); a cloud model; changing which questions skip the model; Filipino-language quality of open replies beyond the checks above.

## Evidence

All from `docs/ai.md` on `spike/oos-chat-eval`, `spike/lfm25-eval` and `ai/lar-voice` (2026-10-15 and 2026-10-25, Apple Silicon Metal, release build, greedy, one run per cell). Hand-labelled by reading the replies. These are Mac numbers on small sets; they say nothing about a phone, and a single label is one run of one prompt, not a rate.

| | Gemma 3 1B | Qwen3 1.7B |
|---|---|---|
| Open eval, grounded (8 questions with an answer) | 7/8 | 8/8 |
| Open eval, refusals (7 with none), old prompt | 5/7 | 4/7 |
| Near-miss questions (12) that got an invented answer | 2 | 7 |
| All 49 out-of-scope: refused / invented | 37 / 4 | 31 / 8 |
| Filipino or Taglish questions answered in Filipino (of 21 that reached the model) | 7 | 4 |
| Refused in the first sentence, then answered anyway (d2, d6, d11, d12, c12) | d6 only | all five |
| Model latency, Mac, median (open eval) | 2.2 s | 1.7 s |

What this means, honestly:

- Qwen is better at finding an answer that is in the notes (8/8) and as fast on the Mac. It is worse where it matters for trust: it invents on most near-miss questions (a note about preorder traversal answers a question about postorder; quiz topics become finals topics "as mentioned in the notes"), answers Filipino in English more often, refuses and then answers, and copies the persona's example sentences.
- Gemma refuses more, so it invents less but also falsely refuses controls (4 of 10 against Qwen's 3, three of them from the Due and Grades rules, not the model).
- The raised relevance floor barely touches near-miss questions, because they share their topic with a note by design. The post-checks are therefore not a certain fix, and the flip is conditional on them and on the suite (C16, C18). If they do not hold, Gemma stays the default.
- An explicit "reply in Filipino" line made Qwen loop and did nothing for Gemma (voice eval). The language rule (C12) is the replacement.
- LFM2.5-1.2B was evaluated and is not a candidate here: it false-refused 6 of 10 controls.

## Test map

| Criterion | Check |
|---|---|
| C1 | `cargo test -p intportal-ai default_chat_is_qwen…`; `vitest` that the size string equals catalog sizes; fresh install on the iPhone 17 simulator gets Qwen and nomic |
| C2 | `vitest` that the smaller option downloads Gemma and nomic only, and replaces Add when `fits` is `refuse`; screenshot of both |
| C3 | `vitest` on `chatModel()` for: nothing installed, only Gemma, only Qwen, both, only nomic; each returns the table's model |
| C4 | screenshot on a simulator with Gemma and nomic copied in: card shows "On · Gemma 3 1B" and "Update IntAssis · 1.11 GB" |
| C5 | `vitest` that a question during the download calls `ai_ask` and Gemma stays loaded; `cargo test -p intportal-llm` resume and wrong-hash tests |
| C6 | `cargo test` on `AiState` with fake loaders: after the swap one chat slot loaded, embedder's untouched, a failing load restores the old model; busy test that the swap waits for a reply to end |
| C7 | `vitest` and simulator relaunch: same `ai_history` before and after; embedder not re-indexed |
| C8 | `cargo test` that delete removes the file and `.part`; `vitest` for the answer after removing the default; screenshot of the confirm |
| C9 | `vitest` that the confirm line sums all installed sizes; `cargo test` that all files are gone |
| C10 | `cargo test -p intportal-ai c10_gate_counts_chat_and_embedder…` at 4.0 GB (Ok), 2.5 GB (Warn), 1.8 GB (Refuse) for Qwen3 1.7B plus nomic; screenshots of both lines |
| C11 | `vitest` that no `ai_download` call happens on open, relaunch, app update or reconnect; relaunch with a `.part` file |
| C12 | `cargo test -p intportal-ai c12_no_language_directive…` (prompt text has none); Filipino and English refusals chosen by `is_filipino`; suite language cases |
| C13 | `cargo test -p intportal-ai c13_refusal_then_answer_is_trimmed…` with `FakeLlm` returning each of d2, d11, d12; scorer test that an untrimmed reply fails |
| C14 | `cargo test -p intportal-ai c14_example_copy_is_replaced…`; scorer test that a copied reply fails |
| C15 | `cargo test` that no hit at the floor gives the canned reply with zero model calls; `embed_eval` rerun in `docs/ai.md` |
| C16 | `cargo run --release -p intportal-llm --example suite -- <gguf>` for Gemma and Qwen; table in `docs/ai.md`; exit code non-zero below threshold |
| C17 | `cargo test -p intportal-ai` that cards, notes and chat build the model's own template; one test per template |
| C18 | Head review of the flip PR with the suite output; `cargo test` runs with the default set to each model |
| C19 | `cargo test -p intportal-ai friendly…` for each row in both languages |
| C20 | phone numbers pasted into `docs/ai.md` and the PR, by the user on the iPhone and by AI on the emulator; no CI check |
| C21 | VoiceOver on the iPhone 17 simulator, TalkBack on the emulator, screenshot at the largest text size |
| C22 | screenshot with Reduce Motion on; `vitest` that the bar's transition is `none` under `prefers-reduced-motion` |

## ADR 0003 addendum (proposal for the Head)

> **Addendum, default chat model.** IntAssis's default chat model is Qwen3 1.7B (about 1.1 GB, plus the 84 MB note-search model). Gemma 3 1B stays in the catalog as a smaller download and as the model of existing installs, which keep working and are offered an update by tap. Only one chat model is ever loaded; the RAM gate counts the chat model plus the note-search model, so a phone that holds both chat models uses about 2.0 GB of storage until the student removes the old one. Nothing downloads without a tap, and the "no AI command writes" and structured-output rules apply to both models identically. The default is Qwen only while the compact suite and the real-phone bar in spec 021 (C16, C20) pass; otherwise the default reverts to Gemma 3 1B.

## Open questions

Resolved from the first draft:

1. Name "Better answers" and "Light": dropped. There is no second card, so no name to pick; "Light" keeps meaning no AI.
2. Whether Qwen can be installed without Gemma: yes. A fresh install downloads Qwen and nomic only, so nobody pays for 0.8 GB they do not use.
3. Where the choice is stored: nowhere. C3 derives the answering model from what is installed, so there is nothing to clear on sign-out.
4. Hold the card back if Qwen refuses fewer questions than Gemma: replaced by the suite gate and the revert criterion (C16, C18).
5. A nudge to try the new model: none. The update line is on the card and nothing more.

Restated:

6. For the user: the C20 bar (3 s to the first word, 10 s median full reply, no kill in the background), now guarding the default and not an optional card. Too strict or too loose? Which phones are the reference devices?
7. For the Head: Wi-Fi wording. The app cannot reliably tell Wi-Fi from mobile data on both platforms, so "Use Wi-Fi" is a hint. Is a hint enough, or should the plugin report the connection?

New:

8. For the user and the Head: the hard categories in C16 include near-miss at 100%. Qwen invented on 7 of 12 and the relevance floor barely helps, so this may only be reachable with the second check named in C15, or not at all. Keep near-miss hard (the flip then may not ship), or move it to the overall score and accept some inventions?
9. For the user: should the flip wait for a clean Filipino-language result? Qwen answers Filipino in English more often (4 of 21 in Filipino, Gemma 7 of 21) and C12 does not fix open replies. This spec accepts it and counts it only in the overall score.
10. For the Head and Android: a 4 GB Android phone. Qwen3 1.7B plus the embedder needs about 1.7 GB, which the gate will warn or refuse on many such phones. Should Android default to Gemma, or rely on C2's automatic smaller option? C20 measures it on the emulator and, for a real 4 GB phone, needs the user's device.
11. For the Head: Gemma removal timing. When does Gemma leave the catalog (and C2, C8 go away): after N releases with no installs, or never? Until then both ship in the catalog and in the tests.
12. For the Head: the final `rag::FLOOR` value, and whether to calibrate it on the user's real note collection or a seeded one.
