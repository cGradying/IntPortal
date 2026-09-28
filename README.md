# IntPortal

An unofficial student portal for PUP's SIS on iOS and Android. It shows your schedule, the next class, your grades with a real GPA, and class reminders, in a hybrid legacy and pixel-art look.

It is a from-scratch rebuild of the macOS IntPortal app. The old app's docs live in `docs/legacy/` and are the reference for every feature.

## Layout

- `src/` is the Svelte 5 interface (SvelteKit, static adapter).
- `src-tauri/` is the Tauri 2 shell for iOS, Android, macOS and Windows. The Rust core crate joins it in the Core crate part.
- `spikes/` holds throwaway probes (S0: SIS over plain HTTP).
- `docs/adr/` records the decisions that are hard to reverse.
- `CONTEXT.md` is the glossary.

## Status

Phase 0: foundation and spikes. The plan and parts are on the wayfinder map issue.

Only your own account is supported, which is what PUP's terms allow.

## Running on the iOS simulator

```bash
scripts/sim.sh
```

It builds the debug app, installs it on the booted simulator and launches it. Tap "Look around with demo data" to skip sign-in.

Needs the iOS simulator runtime that matches your Xcode (`xcodebuild -downloadPlatform iOS`). `pnpm tauri ios dev "<name>"` can pick a real device with the same model name, which then needs signing; install the simulator build directly instead.

## Keep it small

Rust and Xcode builds grow fast; this project once reached hundreds of GB of caches.

- All crates share one Cargo workspace: one `target/` and one `Cargo.lock` at the root. Don't add a crate outside `[workspace] members`.
- Dev builds keep line tables only (`[profile.dev]` in the root `Cargo.toml`).
- `scripts/disk.sh` prints what the builds use. `scripts/clean.sh` deletes this repo's `target/`, the Xcode build folder and this project's DerivedData, and nothing else.
- Never commit build output. Stage paths by name, not `git add -A`.
