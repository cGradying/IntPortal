# IntPortal

An unofficial student portal for PUP's SIS on iOS and Android. It shows your schedule, the next class, your grades with a real GPA, and class reminders, in a hybrid legacy and pixel-art look.

It is a from-scratch rebuild of the macOS IntPortal app. The old app's docs live in `docs/legacy/` and are the reference for every feature.

<p>
  <img src="docs/review/shell-2-today.png" width="200" alt="Today on iPhone">
  <img src="docs/review/android-today.png" width="200" alt="Today on Android">
  <img src="docs/review/android-week.png" width="200" alt="The week on Android">
  <img src="docs/review/android-live-update.png" width="200" alt="The next class as a Live Update on Android">
</p>

## What it does

- **Today:** the next class with a countdown, the day's classes and the free time between them, your own calendar events, and a note for the day.
- **Schedule:** the day and the week. Mark a class in person, online or vacant for one week or every week, move it, colour it.
- **Grades:** the term's GPA on PUP's 1.00 to 5.00 scale, weighted by units, your overall GPA and past terms.
- **Study:** decks of cards with spaced repetition, as flashcards, typed answers or multiple choice.
- **Notes and syllabus:** notes per class and per day, and each subject's grading system and outline.
- **Outside the app:** reminders before class, a home-screen widget, and the next class counting down on the lock screen: a Live Activity in the Dynamic Island on iPhone, a Live Update in the status bar on Android.

Everything stays on the phone. Your login sits in the phone's keychain (the Android Keystore on Android), each student's data is in an encrypted SQLCipher store, and the app only ever talks to PUP SIS. Only your own account is supported, which is what PUP's terms allow.

## Layout

- `src/` is the Svelte 5 interface (SvelteKit, static adapter), shared by both phones.
- `src-tauri/` is the Tauri 2 shell. `gen/apple/` and `gen/android/` are the Xcode and Gradle projects.
- `crates/intportal-core/` is the Rust core: SIS sign-in and scraping, the encrypted store, and the schedule, Today, grades, notes, syllabus, study and coach logic.
- `plugins/` holds the app's own Tauri plugins, each with a Swift and a Kotlin half: `calendar` (the phone's calendar) and `glance` (the widget and the Live Activity or Live Update).
- `spikes/` holds throwaway probes (S0: SIS over plain HTTP).
- `docs/adr/` records the decisions that are hard to reverse. `docs/android.md` is how the Android side is built and run.
- `CONTEXT.md` is the glossary, `DESIGN.md` the look, `PRODUCT.md` the product.

## Status

In development. The plan and parts are on the wayfinder map issue.

## Running on the iOS simulator

```bash
scripts/sim.sh
```

It builds the debug app, installs it on the booted simulator and launches it. Tap "Look around with demo data" to skip sign-in.

Needs the iOS simulator runtime that matches your Xcode (`xcodebuild -downloadPlatform iOS`). `pnpm tauri ios dev "<name>"` can pick a real device with the same model name, which then needs signing; install the simulator build directly instead. `scripts/phone.sh` installs on your own iPhone.

## Running on the Android emulator

```bash
scripts/emu.sh
```

It builds the debug APK, installs it on the running emulator (or a USB phone) and launches it. Tap the portal, then "Look around with demo data" to skip sign-in.

Needs the Android SDK with NDK r28 or newer, JDK 17 and the Rust Android targets (`rustup target add aarch64-linux-android`). Setup, where each Android piece lives, what to check after a change, and the problems already solved are in [docs/android.md](docs/android.md).

Android phones have no Dynamic Island, so the glance sits as a dock above the tab bar, and outside the app the next class shows as a Live Update: a countdown chip in the status bar on Android 16, an ongoing notification before that.

## Keep it small

Rust, Xcode and Gradle builds grow fast; this project once reached hundreds of GB of caches.

- All crates share one Cargo workspace: one `target/` and one `Cargo.lock` at the root. Don't add a crate outside `[workspace] members`.
- Dev builds keep line tables only (`[profile.dev]` in the root `Cargo.toml`).
- `scripts/disk.sh` prints what the builds use. `scripts/clean.sh` deletes this repo's `target/`, the Xcode and Gradle build folders and this project's DerivedData, and nothing else.
- Never commit build output. Stage paths by name, not `git add -A`.
