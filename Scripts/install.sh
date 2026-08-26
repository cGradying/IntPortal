#!/bin/sh
# One-line install/update:
#   curl -fsSL https://raw.githubusercontent.com/cGradying/IntPortal/main/Scripts/install.sh | sh
#
# Downloads the latest .dmg release and installs it to ~/Applications. This
# build is self-signed (no paid Apple Developer account), so two separate
# things stand between a fresh download and it actually launching:
#
#   1. The quarantine flag a curl (or browser) download carries — handled by
#      stripping it below.
#   2. Gatekeeper not recognizing the signing certificate at all — confirmed
#      live: stripping quarantine alone was NOT enough, `spctl -a` kept
#      reporting "rejected" and the app hard-crashed on launch
#      (`codeSigningTrustLevel` in the crash report under
#      ~/Library/Logs/DiagnosticReports/ reads as an outright reject, not a
#      soft warning). Fixed by explicitly trusting the certificate for code
#      signing — the exact same primitive Scripts/make_signing_identity.sh
#      already uses for the local dev identity, just applied here to
#      whatever cert the downloaded build carries, in the user's own login
#      keychain (no sudo, no system-wide change, no admin password).
#
# Both steps are real, visible trust decisions this script makes on your
# machine — not a silent bypass. See the "Trusting..." step below for
# exactly what it does and how to undo it.
#
# Re-running this later is the update path — same steps, overwrites whatever
# is already installed. Sparkle (see Core/UpdaterBridge.swift) still
# auto-updates a running v1.4.0+ install on its own; this script exists for
# the first install, and for anyone who'd rather not deal with the
# browser/dmg/drag dance at all.
set -e

REPO="cGradying/IntPortal"
DEST="$HOME/Applications"
APP="$DEST/PUPSISPortal.app"

echo "Looking up the latest release..."
RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"

# Same shape Core/UpdateCheck.swift already parses (tag_name, and here the
# first .dmg asset's browser_download_url) — no separate endpoint to keep in
# sync with a new release.
VERSION="$(echo "$RELEASE_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/')"
DMG_URL="$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed -E 's/.*"(https:[^"]+)"/\1/')"

if [ -z "$VERSION" ] || [ -z "$DMG_URL" ]; then
  echo "Couldn't find a release to install — check https://github.com/$REPO/releases" >&2
  exit 1
fi

echo "Installing PUPSISPortal $VERSION..."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DMG="$TMP/PUPSISPortal.dmg"
curl -fsSL "$DMG_URL" -o "$DMG"

MOUNT="$TMP/mnt"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet

mkdir -p "$DEST"
rm -rf "$APP"
ditto "$MOUNT/PUPSISPortal.app" "$APP"

hdiutil detach "$MOUNT" -quiet

# Strips the "downloaded from the internet" flag — without it, the app hits
# the same Gatekeeper wall a browser download would.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Trusts the build's signing certificate for code signing, in *your own*
# login keychain only — the same thing Scripts/make_signing_identity.sh does
# for the local dev identity, just for whichever cert this particular
# release was signed with. Confirmed live: quarantine removal alone doesn't
# get past Gatekeeper for a self-signed (non-Apple-issued) certificate; this
# step is what actually does.
# Undo: open Keychain Access, login keychain, find the certificate (its name
# matches codesign's "Authority" below) and delete it.
CERT_DIR="$TMP/cert"
mkdir -p "$CERT_DIR"
if codesign -d --extract-certificates="$CERT_DIR/cert" "$APP" 2>/dev/null && [ -f "$CERT_DIR/cert0" ]; then
  CERT_NAME="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  echo "Trusting the signing certificate (\"$CERT_NAME\") in your login keychain for code signing..."
  security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$CERT_DIR/cert0"
else
  echo "Couldn't extract a certificate to trust — the app may still need a manual right-click > Open on first launch." >&2
fi

echo "Installed PUPSISPortal $VERSION to $APP"
open "$APP"
