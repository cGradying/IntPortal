#!/usr/bin/env bash
# Build the harness for the iOS simulator and run it inside a simulator.
# Usage: run.sh <simulator udid> [section ...]   (sections: avail stream locale tokens guard maxlen latency cancel)
set -euo pipefail
cd "$(dirname "$0")"
udid="${1:?simulator udid}"; shift || true
out="${TMPDIR:-/tmp}/fm-harness"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -target arm64-apple-ios26.0-simulator \
  ../ios/Sources/FoundationCore.swift main.swift -o "$out" 2>&1 | grep -v "incompatible-sysroot" || true
xcrun simctl spawn "$udid" "$out" "$@"
