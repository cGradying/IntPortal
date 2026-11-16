# 053 Desktop: Mac, Windows and Linux

**Status:** building

## What changes for the student

A student without an Android phone, or who wants their schedule on their laptop too, downloads IntPortal for Mac, Windows or Linux from the website. It is the same app, signs in the same way, and keeps its data on that computer.

## Direction and references

Tauri builds the same Rust and Svelte for desktop. The phone layout stays: the window opens phone-sized and can be resized taller. Mobile-only plugins (haptics, biometric, the Live Activity, the camera, the phone calendar) are left out on desktop, as Look around's C5 lines say.

## Keep

- The phone builds' size and speed. The desktop entry point must not bring back the `rlib` that turned off link-time optimisation (#291).
- The keychain promise: on each desktop the login goes to the system's secret store.

## Behaviour

- **C1.** `src-tauri/src/main.rs` starts the app on desktop without adding `rlib` to the library's crate types: it compiles `lib.rs` as its own source with `include!`.
- **C2.** The login is kept in the macOS Keychain, the Windows Credential Manager, or the Linux Secret Service. If Linux has no Secret Service, signing in says so and nothing is written in plain text.
- **C3.** The student's store is encrypted with SQLCipher on every desktop, as on the phone.
- **C4.** The window opens at 430 × 900, keeps a minimum of 360 × 640, and remembers nothing else.
- **C5.** On desktop, You hides the settings that need a phone (Face ID, the class card outside the app, calendar sync, haptics) instead of showing ones that do nothing.
- **C6.** CI builds, on a tag or by hand: `IntPortal-<version>-mac.dmg` (Apple Silicon; Intel Macs later), `IntPortal-<version>-windows.msi`, `IntPortal-<version>-linux.AppImage` and `.deb`, plus version-less copies for the website's links. They are unsigned; the website's install help says how to open them.
- **C7.** IntAssis works on the Mac with the same opt-in download. On Windows and Linux it says it isn't available yet: llama.cpp is built only where it has been tested, and those two get the core's stub.

## Copy

- Linux without a Secret Service: "This computer has no keychain for your login. Install GNOME Keyring or KWallet, then sign in again."

## Data shape

- `src-tauri/Cargo.toml`: `keyring` for macOS, Windows and Linux; SQLCipher with vendored OpenSSL on Windows and Linux.
- `src-tauri/tauri.conf.json`: desktop window size and bundle targets.

## Errors

C2's line. A failed store open says what the phone says.

## Motion and Reduce Motion

As in the app.

## Accessibility

As in the app; keyboard focus works with Tab.

## Out of scope

- Code signing and notarisation (needs paid certificates).
- Auto-update. The Updates link opens the website.
- A desktop layout. The phone layout is the product.

## Test map

| Criterion | Check |
|---|---|
| C1, C3, C6 | the desktop workflow builds all three on a tag |
| C2 | `cargo test` on each desktop runner for the keychain round trip |
| C4, C5 | screenshot on this Mac |
| C7 | a model download and one answer on this Mac |

## Open questions

None.
