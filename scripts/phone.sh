#!/usr/bin/env bash
# Build the app and install it on your own iPhone over USB or Wi-Fi, then open it.
# Usage: APPLE_DEVELOPMENT_TEAM=<team> scripts/phone.sh [--release] [--app-group]
#   --release    the release configuration (what a store build is), not debug
#   DEVICE   the phone's name or id (default: cgradying)
#   --app-group  only with a paid Apple Developer account: lets the
#                home-screen widget read the next class.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APPLE_DEVELOPMENT_TEAM:?set APPLE_DEVELOPMENT_TEAM to your Apple team id}"
device="${DEVICE:-cgradying}"
apple=src-tauri/gen/apple

# The team (and the App Group) go into a regenerated project for this build;
# the committed files come back afterwards when they were clean.
generated=("$apple/intportal.xcodeproj" "$apple"/*/*.entitlements "$apple"/*/Info.plist)
if git diff --quiet -- "${generated[@]}"; then trap 'git checkout -q -- "${generated[@]}"' EXIT; fi

mode=--debug
for a in "$@"; do
  case "$a" in
    --app-group) export INTPORTAL_APP_GROUP=true ;;
    --release) mode= ;;
  esac
done
(cd "$apple" && xcodegen generate --quiet)

rm -rf "$apple/build"
pnpm tauri ios build $mode >/tmp/intportal-phone-build.log 2>&1 || { tail -30 /tmp/intportal-phone-build.log; exit 1; }
xcrun devicectl device install app --device "$device" "$apple/build/arm64/IntPortal.ipa"
xcrun devicectl device process launch --device "$device" ph.intportal.app >/dev/null 2>&1 || echo "Unlock the phone and open IntPortal yourself."
echo "Installed on $device. Apps signed by a free Apple team stop opening after 7 days; run this again to renew."
