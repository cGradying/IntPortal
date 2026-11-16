# Building and running

How to build IntPortal and run it on a simulator, an emulator or your own phone. For what the app is, see the [README](../README.md); for how it is put together, see [ARCHITECTURE.md](ARCHITECTURE.md).

## What you need

- macOS with Xcode and the iOS simulator runtime that matches it (`xcodebuild -downloadPlatform iOS`)
- Rust (stable) with the iOS and WebAssembly targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim wasm32-unknown-unknown`
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
node scripts/commands-check.mjs
node scripts/style-lint.mjs
node scripts/tap-targets.mjs
```

CI runs the same on every pull request, plus clippy. `commands-check` keeps the commands the shell registers and the ones the interface calls in step; `style-lint` holds type sizes, durations and corners to the tokens in `DESIGN.md`; `tap-targets` holds every button to 44 pt. Each push to `main` also builds the iOS simulator app, and each `android-v*` tag builds the Android release APK.

### iOS simulator

```bash
scripts/sim.sh "iPhone 17 Pro Max"
```

The argument is a simulator name or id; with none, the booted simulator is used. The script builds the debug app, installs it and launches it. Tap **Look around first** to skip sign-in, then **Step through**.

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

With an emulator running (or a phone on USB), the script builds the arm64 debug APK, installs it and launches it. Tap **Look around first**, then **Step through**. Where each Android piece lives, what to check after a change and the problems already solved are in [android.md](android.md).

### Changing native settings

`src-tauri/gen/apple/project.yml` owns the Info.plist keys, entitlements and deployment target. After editing it, regenerate the project:

```bash
cd src-tauri/gen/apple && xcodegen generate
```

## Keep it small

Rust, Xcode and Gradle builds grow fast; this project once reached hundreds of GB of caches.

- All crates share one Cargo workspace: one `target/` and one `Cargo.lock` at the root. Don't add a crate outside `[workspace] members`.
- Every worktree shares one Cargo build cache in `~/.cargo/build/intportal` (`.cargo/config.toml`), so a new worktree doesn't compile the dependencies again. Each keeps its own `target/` for the final app.
- Dev builds keep line tables only (`[profile.dev]` in the root `Cargo.toml`). Never set `debug = false` for dependencies, because the iOS link then fails.
- `scripts/disk.sh` prints what the builds use. `scripts/clean.sh` deletes this repo's `target/`, the shared build cache, the Xcode and Gradle build folders and this project's DerivedData, and nothing else.
- Never commit build output. Stage paths by name, not `git add -A`.

## Contributing

Each change is its own issue, branch and pull request. Write the failing test first where a cheap test exists, then the change, then run the checks above. Check UI changes on the iOS simulator, and on the Android emulator when they touch Android. Use the terms in [CONTEXT.md](../CONTEXT.md), and record a hard-to-reverse decision as an ADR in [adr/](adr/).
