#!/usr/bin/env bash
# The App Group is opt-in: a free Apple team can't sign with it. Checks that
# the default project leaves it out and INTPORTAL_APP_GROUP=true puts it in.
set -euo pipefail
cd "$(dirname "$0")/../src-tauri/gen/apple"
files=(intportal_iOS/intportal_iOS.entitlements IntPortalWidget/IntPortalWidget.entitlements)
trap 'xcodegen generate --quiet' EXIT

xcodegen generate --quiet
for f in "${files[@]}"; do
  if grep -q application-groups "$f"; then echo "FAIL: $f has the App Group by default"; exit 1; fi
done

INTPORTAL_APP_GROUP=true xcodegen generate --quiet
for f in "${files[@]}"; do
  grep -q group.ph.intportal.app "$f" || { echo "FAIL: $f lacks the App Group with INTPORTAL_APP_GROUP=true"; exit 1; }
done
echo "ok: App Group is opt-in"
