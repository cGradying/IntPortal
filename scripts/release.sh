#!/usr/bin/env bash
# Builds the signed Android release and the unsigned iPhone app, and makes a
# DRAFT GitHub release with every file under its versioned and its version-less
# name (spec 050 C16). Publishing stays a person's step: see docs/RELEASING.md.
# Usage: scripts/release.sh <notes.md>
set -euo pipefail
cd "$(dirname "$0")/.."
notes="${1:?release notes file}"
version=$(node -p 'require("./src-tauri/tauri.conf.json").version')
tag="android-v$version"
git diff --quiet || { echo "Commit first: the release is built from a clean tree." >&2; exit 1; }

INSTALL=0 scripts/emu.sh --release >/dev/null || { echo "Android build failed; see /tmp/intportal-emu-build.log" >&2; exit 1; }
cp "dist/IntPortal-$version.apk" dist/IntPortal.apk
scripts/ipa.sh

files=("dist/IntPortal-$version.apk" dist/IntPortal.apk "dist/IntPortal-$version.aab" "dist/IntPortal-$version-unsigned.ipa" dist/IntPortal-unsigned.ipa)
(cd dist && shasum -a 256 "IntPortal-$version.apk" "IntPortal-$version.aab" "IntPortal-$version-unsigned.ipa")
gh release create "$tag" --draft --target "$(git rev-parse HEAD)" --title "IntPortal $version" --notes-file "$notes" "${files[@]}"
echo "Draft $tag made. It goes public only when the owner says publish: gh release edit $tag --draft=false"
