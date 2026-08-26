#!/bin/sh
# Builds PUPSISPortal in release mode and installs it as a real .app bundle
# so macOS (and Spotlight) can see it. Usage: Scripts/make_mac_app.sh [dest-dir]
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${1:-$HOME/Applications}"
APP="$DEST_DIR/PUPSISPortal.app"
BUNDLE_ID="com.cgradying.pupsisportal"
# Git tags are already the single source of truth (CI derives VERSION the
# same way from GITHUB_REF_NAME) — no more hand-edited fallback going stale.
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
# Sparkle's public EdDSA key (Info.plist SUPublicEDKey) — pairs with the
# private key held in the login Keychain (Scripts/make_mac_app.sh never
# touches it) and, for CI, the SPARKLE_ED_PRIVATE_KEY repo secret. Rotating
# this key strands every installed app's ability to verify future updates —
# don't regenerate it casually.
SPARKLE_PUBLIC_ED_KEY="z5o63RKeioPEdrM0+1v9VVPA35kU1zQ1b3NsMxW2kKo="

cd "$ROOT"
echo "Building PUPSISPortal (release)..."
swift build -c release --product PUPSISPortal

BIN="$(swift build -c release --product PUPSISPortal --show-bin-path)/PUPSISPortal"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PUPSISPortal"

# Bundle the web notes editor (CodeMirror + KaTeX, offline) into Resources.
NOTES_BUNDLE="$ROOT/Sources/PUPSISPortalApp/Resources/notes-editor.bundle.js"
[ -f "$NOTES_BUNDLE" ] && cp "$NOTES_BUNDLE" "$APP/Contents/Resources/notes-editor.bundle.js"

# Bundled fonts (FontLibrary.swift), same convention as notes-editor.bundle.js
# above — a plain copy into Contents/Resources, read back via Bundle.main.
# NOT SwiftPM's Bundle.module: confirmed the hard way that its generated
# accessor checks Bundle.main.bundleURL (the .app's own root) for a
# "PUPSISPortal_PUPSISPortal.bundle" folder, and a Swift fatalError inside
# that accessor's lazy static init can't be caught — it just crashes, on
# every real launch, silently missed by `swift build`/`swift test` because
# dev builds resolve the same accessor differently. Placing that bundle at
# the app's top level to satisfy it was tried and rejected: codesign's
# --verify --strict correctly refuses "unsealed contents present in the
# bundle root" for anything outside Contents/.
FONTS_DIR="$ROOT/Sources/PUPSISPortalApp/Resources/Fonts"
[ -d "$FONTS_DIR" ] && ditto "$FONTS_DIR" "$APP/Contents/Resources/Fonts"

# Embed Sparkle.framework for in-app auto-update. SwiftPM's Package.swift
# fetches it as a prebuilt XCFramework (not source) into .build/artifacts —
# Xcode would normally do this embedding step for us; a hand-rolled bundle
# has to do it by hand. `ditto`, not `cp -R`: the framework's own code
# signature is computed over its Versions/Current symlinks, which only
# `ditto` preserves faithfully.
SPARKLE_FW="$(find "$ROOT/.build/artifacts" -type d -name 'Sparkle.framework' -path '*/macos-*' -print -quit)"
[ -n "$SPARKLE_FW" ] || { echo "Sparkle.framework not found under .build/artifacts — run swift build first" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>PUPSISPortal shows your calendar events beside your class schedule, and can add your classes to Calendar.</string>
  <key>SUFeedURL</key><string>https://github.com/cGradying/IntPortal/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  $ICON_ARG
</dict>
</plist>
EOF

# Prefer a stable identity over ad-hoc: ad-hoc signing changes the app's code
# identity on every build, which invalidates the Keychain ACL (blocks on a
# credential prompt at launch) and, worse, breaks Sparkle's signing-continuity
# check between releases. Two names because dev machines and CI keep separate
# identities: "PUPSISPortal Local Signing" (Scripts/make_signing_identity.sh,
# one-time per dev machine) and "PUPSISPortal CI Signing" (imported fresh each
# CI run from the MACOS_SIGNING_P12 secret) — either is fine, as long as it's
# the SAME one release to release.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)"
if echo "$IDENTITIES" | grep -qF "PUPSISPortal Local Signing"; then
  SIGN_ID="PUPSISPortal Local Signing"
elif echo "$IDENTITIES" | grep -qF "PUPSISPortal CI Signing"; then
  SIGN_ID="PUPSISPortal CI Signing"
else
  SIGN_ID="-"
fi

# Sparkle can rotate a code-signing identity release to release, but it can
# never accept an update that DROPS signing entirely (SUUpdateValidator:
# "supports rotation, but not removal of Apple Code Signing identity"). A CI
# run that silently fell back to ad-hoc would still install fine today, but
# would permanently strand every already-installed copy the next time a real
# identity comes back — so refuse outright rather than let that happen.
if [ "${CI:-}" = "true" ] && [ "$SIGN_ID" = "-" ]; then
  echo "refusing to build a CI release ad-hoc signed — import the signing identity first" >&2
  exit 1
fi

# Sign inside-out, app last. Sparkle's own docs call out `--deep` as "a
# common source of errors" here: Downloader.xpc carries entitlements the
# other nested binaries must not inherit, so each item needs its own
# invocation rather than one recursive pass.
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_ID" --options runtime \
  "$FW/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_ID" --options runtime --preserve-metadata=entitlements \
  "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_ID" --options runtime \
  "$FW/Versions/B/Autoupdate"
codesign --force --sign "$SIGN_ID" --options runtime \
  "$FW/Versions/B/Updater.app"
codesign --force --sign "$SIGN_ID" "$FW"
# Deliberately no --options runtime on the app itself: hardened runtime
# enables Library Validation, and under the ad-hoc dev fallback every
# rebuild is a different identity, so the app would refuse to load its own
# (differently-signed) framework.
codesign --force --sign "$SIGN_ID" "$APP"

codesign --verify --strict --verbose=2 "$APP"
plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist" >/dev/null

touch "$APP"
mdimport "$APP" >/dev/null 2>&1 || true

echo "Installed $APP"
echo "Spotlight: press Cmd+Space and search PUPSISPortal (may take a few seconds to index)"
