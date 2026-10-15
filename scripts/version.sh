#!/usr/bin/env bash
# Set the app's version in every file that carries it.
# Usage: scripts/version.sh 0.1.5
# Then add the release's section to CHANGELOG.md and open a release/<version> PR.
set -euo pipefail
cd "$(dirname "$0")/.."
v="${1:?version, e.g. 0.1.5}"
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not x.y.z: $v" >&2; exit 1; }

# Each edit replaces only the first matching line of that file.
sed -i '' -E '1,/"version": "[^"]*"/s/"version": "[^"]*"/"version": "'"$v"'"/' package.json src-tauri/tauri.conf.json
sed -i '' -E '/^\[workspace\.package\]/,/^version/s/^version = "[^"]*"/version = "'"$v"'"/' Cargo.toml
sed -i '' -E 's/(CFBundle(ShortVersionString|Version): )"?[0-9.]+"?/\1"'"$v"'"/' src-tauri/gen/apple/project.yml
for plist in src-tauri/gen/apple/intportal_iOS/Info.plist src-tauri/gen/apple/IntPortalWidget/Info.plist; do
  plutil -replace CFBundleShortVersionString -string "$v" "$plist"
  plutil -replace CFBundleVersion -string "$v" "$plist"
  [ -n "$(tail -c1 "$plist")" ] && echo >> "$plist" # plutil drops the final newline
done
cargo metadata --format-version 1 >/dev/null # rewrites Cargo.lock with the new version

git diff --stat
