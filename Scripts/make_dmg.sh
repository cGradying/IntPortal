#!/bin/sh
# Builds PUPSISPortal.app and packages it into a distributable .dmg with an
# /Applications drop target. Usage: Scripts/make_dmg.sh [version]
#
# Standalone "-with-AI" variant: set BUNDLE_LLAMA_SERVER and BUNDLE_MODELS
# (same env vars make_mac_app.sh reads) before calling this script, and the
# output is named PUPSISPortal-<version>-with-AI.dmg instead — everything
# else (staging, signing, volume layout) is identical either way.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
STAGE="$(mktemp -d)/PUPSISPortal"
SUFFIX=""
[ -n "${BUNDLE_LLAMA_SERVER:-}" ] || [ -n "${BUNDLE_MODELS:-}" ] && SUFFIX="-with-AI"
DMG="$ROOT/dist/PUPSISPortal-$VERSION$SUFFIX.dmg"

# Build a fresh .app into the staging dir (not ~/Applications).
VERSION="$VERSION" "$ROOT/Scripts/make_mac_app.sh" "$STAGE"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil create -volname "PUPSISPortal $VERSION$SUFFIX" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGE"
echo "Built $DMG"
