# Android

The Android app is the same app as iOS: one Svelte interface, one Rust
core, one Tauri shell. Only the native edges differ. This page is how the
Android side is put together and how to build, run and check it.

## Where things live

| Path | What it is |
| --- | --- |
| `src/` | The interface, shared with iOS. Android-only behaviour is in `src/lib/bars.ts` (system bar icons and safe areas) and `src/lib/back.ts` (the back gesture). |
| `src-tauri/src/lib.rs` | The shell's commands. `mod keychain` has an Apple side (Keychain Services) and an Android side (JNI into `Secrets.kt`); `vault` and `dbkey` sit on it. |
| `src-tauri/gen/android/` | The Gradle project, generated once by `pnpm tauri android init` and committed like `gen/apple`. Its build output is ignored. |
| `src-tauri/gen/android/app/src/main/java/ph/intportal/app/MainActivity.kt` | Edge to edge, and the `IntPortalAndroid` JavaScript bridge: `bars()`, `insets()`, `leave()`. |
| `src-tauri/gen/android/app/src/main/java/ph/intportal/app/Secrets.kt` | The Android keychain: values sealed by an AES-GCM key in the Android Keystore, kept in app-private prefs. |
| `src-tauri/gen/android/app/src/main/java/ph/intportal/app/generated/` | Written by wry on every build. Never edit. |
| `plugins/tauri-plugin-calendar/android/` | `CalendarPlugin.kt`: CalendarContract. A local IntPortal calendar for classes, and the student's own events. |
| `plugins/tauri-plugin-glance/android/` | `GlancePlugin.kt`: the home-screen widget and the Live Update (the Dynamic Island's stand-in). |
| `crates/intportal-core/Cargo.toml` | On Android, rusqlite builds SQLCipher with its own OpenSSL (`bundled-sqlcipher-vendored-openssl`). |
| `scripts/emu.sh` | Build, install and launch the debug app. |

The app id is `ph.intportal.app`. minSdk 24, target and compile SDK 36.

## The Dynamic Island on Android

Android phones have a punch-hole camera, not a Dynamic Island, so the glance
takes Android's own shapes:

- **In the app:** the dock above the tab bar (`Glance.svelte`). `watchDynamicIsland` in `src/lib/glance.ts` always answers no on Android.
- **Outside the app:** a Live Update. From an hour before class until it ends, an ongoing notification counts down to the start, then to the end. Android 16 promotes it to a chip in the status bar beside the camera (the `android.requestPromotedOngoing` extra); older versions show it as an ongoing notification. Alarms at each turn (an hour before, start, end) keep it right with the app closed.
- **Home screen:** the "Next class" widget, a copy of the iOS one.
- **Permission:** the glance asks for notifications once, the first time there is a class within the hour, like iOS asking to allow Live Activities.

## One-time setup (macOS)

1. Android Studio, then in its SDK Manager: SDK Platform 36, Build-Tools, Platform-Tools, Emulator, NDK (r28 or newer), Command-line Tools.
2. JDK 17: `brew install openjdk@17`.
3. Rust targets: `rustup target add aarch64-linux-android x86_64-linux-android`.
4. An emulator: in Device Manager, a Pixel with an arm64 system image (API 35 or 36). API 36 is needed to see the status-bar chip.

`scripts/emu.sh` finds the SDK at `~/Library/Android/sdk`, takes the newest NDK and JDK 17 from Homebrew. Set `ANDROID_HOME`, `NDK_HOME` or `JAVA_HOME` to override.

## Run it

```bash
emulator -avd <name> &            # or start it from Android Studio
scripts/emu.sh
```

It builds the frontend and the arm64 debug APK, installs it on the running
emulator (or a USB phone with debugging on) and launches it. The build log
is `/tmp/intportal-emu-build.log`; on failure the script prints the Kotlin
(`e:`) and Rust errors from it. A first build takes several minutes; later
ones a couple.

To look around without an SIS account, tap the portal, then "Look around
with demo data", then "Step through". The demo account is in debug builds
only and lasts until the app is closed. Its store is still encrypted with a
Keystore-sealed key, like a real one.

`pnpm tauri android dev` (live reload) hasn't been tried; `emu.sh` is the
path that's known good.

## Release builds and the beta

```bash
scripts/emu.sh --release
```

This builds the signed release for arm64 and 32-bit arm phones and puts two files in `dist/` (gitignored):

- `IntPortal-<version>.apk` to install directly. This is what goes on the beta.
- `IntPortal-<version>.aab`, the bundle for Google Play.

It then installs the APK on the running emulator or phone. A release can't install over a debug build, because they're signed with different keys. Uninstall the debug app first (`adb uninstall ph.intportal.app`), which wipes its data.

Release builds have no demo account; testers sign in with their own SIS login. R8 shrinks the code. Tauri's own ProGuard rules keep the plugin classes and their arguments, and `Secrets` is kept with `@Keep`.

**The release key** is in `~/.config/intportal/`, outside every checkout:

- `android-release.jks` is the keystore, alias `intportal`.
- `android-keystore.properties` holds its path and password.

`app/build.gradle.kts` reads that file and signs with it. Without the file (CI, another machine), the release comes out unsigned. **Back up both files somewhere safe, like a password manager.** Every later update has to be signed with the same key, or phones refuse to install it over the old one. Never commit them.

**The beta** is a GitHub pre-release tagged `android-v<version>-beta.<n>`, with the APK and the bundle attached. The repo is private, so only its collaborators can download it. To install, open the APK on the phone and allow installs from that source. Play internal testing (#26) needs a Google Play developer account. Once there is one, upload the `.aab` there; Play App Signing then re-signs it with Play's key, and this key becomes the upload key.

Bump `version` in `src-tauri/tauri.conf.json` for each beta. Tauri derives Android's `versionCode` from it, and a phone only installs an update whose code is higher.

## Checking a change

- `pnpm check`, `pnpm test` and `cargo test --workspace` on the host.
- `cargo check -p intportal --target aarch64-linux-android` type-checks the Android-only Rust without Gradle. It needs `ANDROID_HOME`, `NDK_HOME`, the `RANLIB_`/`AR_` variables from `emu.sh`, and `CC_aarch64_linux_android` set to the NDK's `aarch64-linux-android24-clang`.
- On the emulator, with the demo account: Today, Schedule (Day and Week), a class sheet, a note, Grades, Study, You. Compare with the same screens on the iOS simulator (`scripts/sim.sh`).
- Back gesture: closes the top sheet or page, then goes to Today, then backgrounds the app.
- Status bar icons: light over the dark landing, dark over the Day room.
- Calendar: in You, "Keep classes in my calendar" asks, then makes the IntPortal calendar. Check it with `adb shell content query --uri content://com.android.calendar/calendars`.
- Glance: within an hour of a class, the notification shows in the shade. Add the widget from the launcher's Widgets list.
- Store encrypted: `adb shell run-as ph.intportal.app head -c 16 /data/data/ph.intportal.app/<store>.sqlite | xxd` must not start with `SQLite format 3`.

## Things that bit before

- **`aarch64-linux-android-ranlib: command not found`** while building OpenSSL: the NDK only ships `llvm-ranlib`. `emu.sh` sets `RANLIB_aarch64_linux_android` and `AR_aarch64_linux_android`.
- **`ClassNotFoundException: ph.intportal.glance.GlancePlugin`** at launch: the Rust side registered a plugin whose Gradle module wasn't built yet. Rebuild; a plugin's `build.rs` must call `.android_path("android")`.
- **"Can't load widget":** RemoteViews only inflate the allowed views. A plain `<View>` isn't one; use an empty `FrameLayout`.
- **Platform API missing at compile SDK 36:** `Notification.Builder.setRequestPromotedOngoing` isn't there; set the extra instead.
- **Safe areas read 0:** older WebViews leave `env(safe-area-inset-*)` at 0 under edge to edge. `bars.ts` sets `--safe-top` and `--safe-bottom` on `body` from the bridge (`applyRoom` clears custom properties on the root element, so not there).
- **Back closed the app:** Tauri hands the back press to JavaScript only while an `onBackButtonPress` listener exists. Anything that opens over the page registers its close with `closable()` in an `$effect`.
- **White screen for a few seconds on start:** the emulator's software GPU (`-gpu swiftshader_indirect`). Not seen as a bug on a phone yet.
- **Backups are off** (`allowBackup="false"`): a restored store or login couldn't be opened without the Keystore key, which never leaves the phone.

## Not done yet

- SIS sign-in over the real network on Android hasn't been tried with a live account.
- The status-bar chip needs an Android 16 device or emulator to see.
- Play internal testing (#26): needs a Google Play developer account.
