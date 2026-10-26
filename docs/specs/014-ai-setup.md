# 014 Set up your study buddy at first run

**Status:** draft, wording to confirm

## What changes for the student

After signing in, the first run asks four short things before anything else: what to call the AI, what the AI calls the student, which language, and which tone. It takes about 30 seconds, every field can be skipped, and every answer can be changed later on You. Then the student picks Light or With AI as today.

## Direction and references

- Today's first run (`src/lib/FirstRun.svelte`): "Meet IskoLAR", "Everything stays on this phone", "Light, or with AI?", "Want a heads-up before class?". It introduces LAR but asks nothing.
- The "How LAR talks to me" note on the IntAssis card (spec 020 C12/C13, `crates/intportal-ai/src/persona.rs` `STYLE_MAX`), which this setup sits beside.
- LAR and Isko are the app's mascots (`docs/legacy/CONTEXT.md`); the art stays LAR whatever name the student picks.

## Keep

- The four existing steps and their order after the new step; Light stays the default and nothing downloads without a tap.
- The mascot art and the orb.
- The style note on the IntAssis card.

## Behaviour

- **C1.** First run gains one step, right after "Meet IskoLAR": "Set up your study buddy". It is one screen with four fields.
- **C2.** "Call me" field: the AI's name. Default "LAR". 1 to 20 characters; letters, numbers, spaces, hyphen and apostrophe only.
- **C3.** "I'll call you" field: the student's nickname. Default "Isko" (or "Iska" when chosen with one tap). 1 to 20 characters, same character rule.
- **C4.** Language: three chips, English, Filipino, Taglish. Default Taglish.
- **C5.** Tone: three chips, Chill, Friendly, Formal. Default Friendly.
- **C6.** "Skip" keeps every default and moves on; "Next" saves and moves on. The step never blocks.
- **C7.** You → IntAssis gains the same four fields under "Your study buddy"; a change takes effect on the next message.
- **C8.** The name and nickname flow into: the chat sheet title and message labels, the persona prompt's identity line ("You are {name} …", "the student likes to be called {nickname}"), rule answers' lead-ins, and LAR's notifications ("{name}: Math 101 in 10 minutes").
- **C9.** Language sets the default reply language for rule answers and the example turns when the student's message does not show a language (short or mixed messages). A clearly English or Filipino message is still answered in its own language.
- **C10.** Tone adds one line to the persona: Chill (casual, short, light humour), Friendly (today's voice), Formal (polite, no slang, "po" in Filipino).
- **C11.** The fields are stored on the phone only, cleared on sign-out with the rest of the student's data, and never sent anywhere.
- **C12.** The name and nickname are inserted as data, never as instructions: newlines and anything outside C2's character rule are stripped before they reach the prompt.
- **C13.** In Light mode (no model) the name, nickname, language and tone still apply to the app's own replies and labels.

## Copy

- Title: "Set up your study buddy"
- Body: "A few quick choices. You can change them any time on You."
- Labels: "Call me", "I'll call you", "Language", "Tone"
- Chips: "English", "Filipino", "Taglish"; "Chill", "Friendly", "Formal"
- Buttons: "Next", "Skip"
- Preview line under the fields, live: "{name}: Hi {nickname}! Ready to study?" (Filipino: "{name}: Uy {nickname}! Tara, aral tayo?")

## Data shape

- A small settings record `{ name, nickname, language, tone }` saved where the style note lives today (`src/lib/assis/assis.svelte.ts`), passed to `ai_ask` beside `style`.
- `crates/intportal-ai/src/persona.rs`: identity line built from the name and nickname; one tone line; language default for example selection (`crates/intportal-ai/src/lang.rs`).

## Errors

- A name with only stripped characters falls back to the default and says "Using LAR for now."

## Motion and Reduce Motion

Same step transition as the other first-run steps; the preview line updates without animation under Reduce Motion.

## Accessibility

Fields have visible labels; chips are a radio group with the selected one announced; the step is reachable with the keyboard and screen reader in field order.

## Out of scope

- Changing the mascot art or voice audio.
- A tone or personality beyond the three chips.

## Test map

| Criterion | Check |
|---|---|
| C1–C7 | vitest for the setup store and validation; screenshot on the UI simulator |
| C8–C10, C12 | `cargo test -p intportal-ai` that the identity, tone and language default reach the prompt and stripped input cannot add lines |
| C11 | vitest that sign-out clears the record |
| C13 | vitest of rule-answer labels in Light mode |

## Open questions

1. Is Taglish the right default language, and Friendly the right default tone?
2. Should the nickname default be empty (no name used) instead of "Isko"?
