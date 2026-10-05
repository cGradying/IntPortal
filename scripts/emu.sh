#!/usr/bin/env bash
# Build the review (debug) app for Android, install it on the running
# emulator (or a USB phone) and launch it. The Android counterpart of sim.sh.
# Usage: scripts/emu.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export NDK_HOME="${NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* | sort -V | tail -1)}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
# SQLCipher's vendored OpenSSL looks for <triple>-ranlib, which the NDK
# replaced with llvm-ranlib.
bin="$(ls -d "$NDK_HOME"/toolchains/llvm/prebuilt/*/bin | head -1)"
export RANLIB_aarch64_linux_android="$bin/llvm-ranlib" AR_aarch64_linux_android="$bin/llvm-ar"
pnpm tauri android build --debug --target aarch64 --apk >/tmp/intportal-emu-build.log 2>&1 || { grep -E "^e: |error" /tmp/intportal-emu-build.log | head -20; exit 1; }
adb="$ANDROID_HOME/platform-tools/adb"
"$adb" install -r src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk
"$adb" shell am start -n ph.intportal.app/.MainActivity
