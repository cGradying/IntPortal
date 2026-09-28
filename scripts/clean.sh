#!/usr/bin/env bash
# Delete IntPortal's rebuildable build output. Touches only this repo's
# target/ and Xcode build folder, and this project's DerivedData.
set -euo pipefail
cd "$(dirname "$0")/.."
before=$(df -k / | awk 'NR==2 {print $4}')
cargo clean
rm -rf src-tauri/gen/apple/build
rm -rf ~/Library/Developer/Xcode/DerivedData/intportal-*
after=$(df -k / | awk 'NR==2 {print $4}')
echo "Freed $(( (after - before) / 1024 / 1024 )) GB."
