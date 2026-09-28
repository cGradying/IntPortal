#!/usr/bin/env bash
# Build the review (debug) app for the booted iOS simulator, install it and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf src-tauri/gen/apple/build
pnpm tauri ios build --target aarch64-sim --debug >/tmp/intportal-sim-build.log 2>&1 || { tail -30 /tmp/intportal-sim-build.log; exit 1; }
xcrun simctl terminate booted ph.intportal.app 2>/dev/null || true
xcrun simctl install booted src-tauri/gen/apple/build/arm64-sim/IntPortal.app
xcrun simctl launch booted ph.intportal.app
