# On-device AI runs llama.cpp in Rust; local only

IntAssis answers with a small model that runs on the student's phone through llama.cpp, using the `llama-cpp-2` crate. No cloud key and no server are involved, so [ADR 0002](0002-device-only-data.md) stands.

## Decisions

- **Engine.** llama.cpp covers iOS and Android on any phone with 4 GB of RAM or more, and runs under cargo on the Mac. Apple Foundation Models and Gemini Nano may come later as a faster backend behind the same `Llm` trait; neither supports Filipino today and both need a flagship phone. The rule-based coach stays as the fallback either way.
- **Layering.** `crates/intportal-ai` is pure Rust and tested with a fake model. `crates/intportal-llm` holds llama.cpp and is a stub on Linux, so Linux CI never compiles it. A separate crate, not a cargo feature, because a feature switched on anywhere in the workspace would pull llama.cpp into every build.
- **Opt-in download.** Models are never bundled. The student sees the size first, the download resumes and is checked against a pinned SHA-256, and a Storage view deletes it. Files sit in the app data folder, excluded from backup.
- **No AI command writes.** The model proposes; the UI shows a confirm card, and Apply calls the existing commands.
- **Structured output.** Replies are constrained by a JSON schema built at run time, because small models call tools badly. The model never computes dates.

- **Light or with AI.** The app works fully without IntAssis's model. Setup offers "Light" (no AI, nothing downloaded) and "With AI" (shows the model size, then downloads); Storage can add or remove the model later. The shell also gets a cargo feature `ai`, on by default, so a lite build can leave out llama.cpp. A0 measures the size delta to decide whether that build is worth shipping.

## Consequences

- A model needs 0.4 to 1.1 GB of storage and, while loaded, enough free memory. A RAM gate warns above 60% of available memory and refuses above 90%. The model unloads when the app is hidden.
- Cloud IntAssis needs its own ADR, since it supersedes ADR 0002 for opted-in users.
- App Review guideline 2.5.2 on downloaded model files is a low risk, retired at the first review (#26).
