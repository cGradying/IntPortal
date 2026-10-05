#!/usr/bin/env bash
# Delete IntPortal's rebuildable build output. Touches only this repo's
# target/, the Cargo build cache every worktree shares, the Xcode and
# Gradle build folders, and this project's DerivedData.
set -euo pipefail
cd "$(dirname "$0")/.."
before=$(df -k / | awk 'NR==2 {print $4}')
cargo clean
rm -rf ~/.cargo/build/intportal
rm -rf src-tauri/gen/apple/build
rm -rf src-tauri/gen/android/app/build src-tauri/gen/android/build src-tauri/gen/android/.gradle plugins/*/android/build
rm -rf ~/Library/Developer/Xcode/DerivedData/intportal-*
after=$(df -k / | awk 'NR==2 {print $4}')
echo "Freed $(( (after - before) / 1024 / 1024 )) GB."
