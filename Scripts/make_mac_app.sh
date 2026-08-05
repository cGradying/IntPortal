#!/bin/sh
# Builds PUPSISPortal in release mode and installs it as a real .app bundle
# so macOS (and Spotlight) can see it. Usage: Scripts/make_mac_app.sh [dest-dir]
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${1:-$HOME/Applications}"
APP="$DEST_DIR/PUPSISPortal.app"
BUNDLE_ID="com.cgradying.pupsisportal"

cd "$ROOT"
echo "Building PUPSISPortal (release)..."
swift build -c release --product PUPSISPortal

BIN="$(swift build -c release --product PUPSISPortal --show-bin-path)/PUPSISPortal"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PUPSISPortal"

ICON_PNG="$ROOT/Sources/PUPSISPortalApp/Resources/pupsisportal-icon.png"
ICON_ARG=""
if [ -f "$ICON_PNG" ]; then
  ICONSET="$(mktemp -d)/PUPSISPortal.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/PUPSISPortal.icns"
  ICON_ARG="<key>CFBundleIconFile</key><string>PUPSISPortal.icns</string>"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PUPSISPortal</string>
  <key>CFBundleDisplayName</key><string>PUPSISPortal</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>PUPSISPortal</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  $ICON_ARG
</dict>
</plist>
EOF

# Prefer the stable identity from Scripts/make_signing_identity.sh: ad-hoc
# signing changes the app's code identity on every build, which invalidates
# the Keychain ACL and makes the app block on a credential prompt at launch.
SIGN_ID="PUPSISPortal Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

touch "$APP"
mdimport "$APP" >/dev/null 2>&1 || true

echo "Installed $APP"
echo "Spotlight: press Cmd+Space and search PUPSISPortal (may take a few seconds to index)"
