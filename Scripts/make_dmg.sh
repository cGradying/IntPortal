#!/bin/sh
# Builds PUPSISPortal.app and packages it into a distributable .dmg with an
# /Applications drop target. Usage: Scripts/make_dmg.sh [version]
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.2.0}"
STAGE="$(mktemp -d)/PUPSISPortal"
DMG="$ROOT/dist/PUPSISPortal-$VERSION.dmg"

# Build a fresh .app into the staging dir (not ~/Applications).
VERSION="$VERSION" "$ROOT/Scripts/make_mac_app.sh" "$STAGE"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil create -volname "PUPSISPortal $VERSION" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGE"
echo "Built $DMG"
