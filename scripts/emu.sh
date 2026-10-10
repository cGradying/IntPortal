#!/usr/bin/env bash
# Build the review (debug) app for Android, install it on the running
# emulator (or a USB phone) and launch it. The Android counterpart of sim.sh.
# Usage: scripts/emu.sh [--release]
#   --release  the signed release build instead, for arm64 and 32-bit arm
#              phones, as an APK and a Play bundle in dist/. Signed with the
#              key in ~/.config/intportal (see docs/android.md).
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export NDK_HOME="${NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* | sort -V | tail -1)}"
export ANDROID_NDK_ROOT="$NDK_HOME" # llama.cpp's build script reads this one
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
# SQLCipher's vendored OpenSSL looks for <triple>-ranlib, which the NDK
# replaced with llvm-ranlib.
bin="$(ls -d "$NDK_HOME"/toolchains/llvm/prebuilt/*/bin | head -1)"
export RANLIB_aarch64_linux_android="$bin/llvm-ranlib" AR_aarch64_linux_android="$bin/llvm-ar"
export RANLIB_armv7_linux_androideabi="$bin/llvm-ranlib" AR_armv7_linux_androideabi="$bin/llvm-ar"
log=/tmp/intportal-emu-build.log
outputs=src-tauri/gen/android/app/build/outputs
if [ "${1:-}" = "--release" ]; then
  [ -f ~/.config/intportal/android-keystore.properties ] || { echo "No release key in ~/.config/intportal; see docs/android.md." >&2; exit 1; }
  pnpm tauri android build --target aarch64 --target armv7 --apk --aab >"$log" 2>&1 || { grep -E "^e: |error" "$log" | head -20; exit 1; }
  version=$(node -p 'require("./src-tauri/tauri.conf.json").version')
  mkdir -p dist
  cp "$outputs/apk/universal/release/app-universal-release.apk" "dist/IntPortal-$version.apk"
  cp "$outputs/bundle/universalRelease/app-universal-release.aab" "dist/IntPortal-$version.aab"
  apk="dist/IntPortal-$version.apk"
  ls -lh dist/IntPortal-"$version".*
else
  pnpm tauri android build --debug --target aarch64 --apk >"$log" 2>&1 || { grep -E "^e: |error" "$log" | head -20; exit 1; }
  apk="$outputs/apk/universal/debug/app-universal-debug.apk"
fi
adb="$ANDROID_HOME/platform-tools/adb"
"$adb" install -r "$apk"
"$adb" shell am start -n ph.intportal.app/.MainActivity
