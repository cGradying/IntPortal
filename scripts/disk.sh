#!/usr/bin/env bash
# Print how much disk IntPortal's builds use. Read-only.
cd "$(dirname "$0")/.."
size() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1 || echo "-"; }
row() { printf '%-28s %s\n' "$1" "$(size "$2")"; }
row "target/ (Rust)" target
row "src-tauri/gen/apple/build" src-tauri/gen/apple/build
row "node_modules" node_modules
for d in ~/Library/Developer/Xcode/DerivedData/intportal-*; do
  [ -e "$d" ] && row "DerivedData/$(basename "$d" | cut -c1-16)" "$d"
done
row "CoreSimulator (all apps)" ~/Library/Developer/CoreSimulator
row "repo total" .
printf '%-28s %s\n' "disk free" "$(df -h / | awk 'NR==2 {print $4}')"
