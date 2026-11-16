#!/usr/bin/env bash
# Builds the unsigned iPhone app for sideloading (AltStore, SideStore), which
# re-sign it with the student's own Apple ID (spec 050 C17). Writes
# dist/IntPortal-<version>-unsigned.ipa and the version-less copy.
set -euo pipefail
cd "$(dirname "$0")/.."
apple=src-tauri/gen/apple
mkdir -p "$apple/Externals" "$apple/assets" dist
(cd "$apple" && APPLE_DEVELOPMENT_TEAM= INTPORTAL_APP_GROUP=false xcodegen generate --quiet)
pnpm tauri ios build --no-sign --archive-only >/tmp/intportal-ipa.log 2>&1 || { tail -30 /tmp/intportal-ipa.log; exit 1; }
version=$(node -p 'require("./src-tauri/tauri.conf.json").version')
work=$(mktemp -d)
mkdir "$work/Payload"
cp -R "$apple/build/intportal_iOS.xcarchive/Products/Applications/IntPortal.app" "$work/Payload/"
(cd "$work" && zip -qry IntPortal.ipa Payload)
cp "$work/IntPortal.ipa" "dist/IntPortal-$version-unsigned.ipa"
cp "$work/IntPortal.ipa" dist/IntPortal-unsigned.ipa
ls -lh dist/IntPortal-*unsigned.ipa
