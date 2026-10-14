#!/usr/bin/env bash
# Build the review (debug) app, install it on a simulator and launch it.
# Usage: scripts/sim.sh [device name or UDID]; default is the booted one.
set -euo pipefail
cd "$(dirname "$0")/.."
device="${1:-booted}"
# project.yml is the source of truth; the committed project can be stale (it lacked Accelerate for llama.cpp).
(cd src-tauri/gen/apple && APPLE_DEVELOPMENT_TEAM= INTPORTAL_APP_GROUP=false xcodegen generate --quiet)
rm -rf src-tauri/gen/apple/build
pnpm tauri ios build --target aarch64-sim --debug >/tmp/intportal-sim-build.log 2>&1 || { tail -30 /tmp/intportal-sim-build.log; exit 1; }
xcrun simctl terminate "$device" ph.intportal.app 2>/dev/null || true
xcrun simctl install "$device" src-tauri/gen/apple/build/arm64-sim/IntPortal.app
xcrun simctl launch "$device" ph.intportal.app
