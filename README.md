# IntPortal

An unofficial student portal for PUP's SIS, built for phones. It signs in to the SIS with your own account, keeps your schedule and grades on the phone, and adds study tools around them. The look is a calm, clean interface with crafted pixel-art moments. LAR, the Lakbay-Aral Robot, does the talking. Isko is you.

It is a from-scratch rebuild of the macOS IntPortal app. The old app's docs live in `docs/legacy/` and are the reference for every feature.

Only your own account is supported, which is what PUP's terms allow.

<p>
  <img src="docs/review/shell-2-today.png" width="200" alt="Today on iPhone">
  <img src="docs/review/android-today.png" width="200" alt="Today on Android">
  <img src="docs/review/android-week.png" width="200" alt="The week on Android">
  <img src="docs/review/android-live-update.png" width="200" alt="The next class as a Live Update on Android">
</p>

## What it does

- **Today.** Up next with a countdown, today's classes with the free time between them, your GPA at a glance, deadlines due soon, and one nudge from LAR.
- **Schedule.** Day and week views. Long-press a class to mark it vacant or online, move it for a week, colour it, or add a note.
- **Grades.** Every term with a real GPA, goals, and what you need on the rest to reach a target.
- **Study.** Flashcard decks scheduled by FSRS, with three ways to study and a daily streak.
- **Syllabus and notes.** Paste a course outline to track quizzes and exams, and keep notes per class or per day.
- **Reminders.** Before each class, the evening before deadlines, and on study days.
- **On the phone itself.** A Live Activity for the next class on Dynamic Island iPhones; on Android, which has no Dynamic Island, a Live Update counting down in the status bar. A home-screen widget on both. An IntPortal calendar in the phone's calendar holds your classes, and your own events show on Today and Schedule as busy time.
- **Privacy.** Everything stays on the phone. Your SIS login is in the keychain (the Android Keystore on Android). Each student's data is its own SQLCipher-encrypted file, with its key in the keychain. A Face ID or fingerprint app lock is optional.

## Stack

- **Core.** Rust, in `crates/intportal-core`: the SIS client and parsers, schedule and grade logic, the coach, FSRS study scheduling, syllabus parsing, calendar events, and the encrypted SQLite store.
- **Shell.** Tauri 2, in `src-tauri`, for iOS and Android. macOS and Windows build from the same code.
- **Interface.** Svelte 5 with SvelteKit's static adapter, in `src`. The landing's 3D pixel portal uses three.js.
- **Native plugins.** Local plugins with a Swift and a Kotlin half live in `plugins/`: `tauri-plugin-glance` (widget, and the Live Activity or Live Update) and `tauri-plugin-calendar` (EventKit or CalendarContract).

## Layout

```
crates/intportal-core/   Rust core and its tests
src-tauri/               Tauri shell: commands, keychain, store opening
src-tauri/gen/apple/     Xcode project, generated from project.yml by XcodeGen
src-tauri/gen/android/   Gradle project, from tauri android init (see docs/android.md)
plugins/                 Local Tauri plugins with Swift and Kotlin sources
src/                     Svelte interface (screens in src/lib/screens)
scripts/                 sim.sh, phone.sh, emu.sh, disk.sh, clean.sh, pentomino-solve.mjs
docs/adr/                Decisions that are hard to reverse
docs/android.md          How the Android side is built, run and checked
CONTEXT.md               Glossary of the app's terms
PRODUCT.md, DESIGN.md    Product record and design system
```

## Requirements

- macOS with Xcode and the iOS simulator runtime that matches it (`xcodebuild -downloadPlatform iOS`)
- Rust (stable) with the iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
- Node 22 and pnpm
- XcodeGen (`brew install xcodegen`)
- For Android: Android Studio with SDK 36, NDK r28 or newer and an emulator, JDK 17 (`brew install openjdk@17`), and `rustup target add aarch64-linux-android`

Then install the JavaScript dependencies:

```bash
pnpm install
```

## Run it

### Checks

```bash
pnpm check
pnpm test
cargo test -p intportal-core
```

CI runs the same on every pull request.

### iOS simulator

```bash
scripts/sim.sh "iPhone 17 Pro Max"
```

The argument is a simulator name or id; with none, the booted simulator is used. The script builds the debug app, installs it and launches it. Tap **Look around with demo data** to skip sign-in, then **Step through**.

`pnpm tauri ios dev` can pick a real device with the same model name, which then needs signing, so prefer `scripts/sim.sh`.

### Your own iPhone

1. Sign in to Xcode with your Apple ID: Xcode → Settings → Accounts.
2. Unlock the phone, then run:

   ```bash
   APPLE_DEVELOPMENT_TEAM=<your team id> scripts/phone.sh
   ```

   `DEVICE=<name or id>` picks the phone. The script regenerates the Xcode project with your team, builds, installs over USB or Wi-Fi, and restores the committed project files.
3. The first time, trust the developer profile: Settings → General → VPN & Device Management.

A free Apple account works, with two limits. The app stops opening after 7 days, so run the script again to renew it. App Groups aren't available, so the home-screen widget can't show the next class; the Live Activity still works. With a paid account, add `--app-group`.

### Android emulator

```bash
scripts/emu.sh
```

With an emulator running (or a phone on USB), the script builds the arm64 debug APK, installs it and launches it. Tap the portal, then **Look around with demo data**, then **Step through**. Where each Android piece lives, what to check after a change and the problems already solved are in [docs/android.md](docs/android.md).

### Changing native settings

`src-tauri/gen/apple/project.yml` owns the Info.plist keys, entitlements and deployment target. After editing it, regenerate the project:

```bash
cd src-tauri/gen/apple && xcodegen generate
```

## Keep it small

Rust, Xcode and Gradle builds grow fast; this project once reached hundreds of GB of caches.

- All crates share one Cargo workspace: one `target/` and one `Cargo.lock` at the root. Don't add a crate outside `[workspace] members`.
- Dev builds keep line tables only (`[profile.dev]` in the root `Cargo.toml`). Never set `debug = false` for dependencies, because the iOS link then fails.
- `scripts/disk.sh` prints what the builds use. `scripts/clean.sh` deletes this repo's `target/`, the Xcode and Gradle build folders and this project's DerivedData, and nothing else.
- Never commit build output. Stage paths by name, not `git add -A`.

## Contributing

Each change is its own branch and pull request. Write the failing test first where a cheap test exists, then the change. Check UI changes on the iOS simulator, and on the Android emulator when they touch Android. Use the terms in `CONTEXT.md`. Record a hard-to-reverse decision as an ADR in `docs/adr/`.
