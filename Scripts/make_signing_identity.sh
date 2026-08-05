#!/bin/sh
# Creates a stable, self-signed code-signing identity in your login keychain,
# so PUPSISPortal keeps the same code identity across rebuilds.
#
# Why: make_mac_app.sh signs ad-hoc (`--sign -`), which derives the signature
# from the binary itself. Every rebuild is therefore a different identity, the
# Keychain ACL for the saved credentials no longer matches, and the app blocks
# on a "wants to use the login keychain" prompt before it can draw a window.
# Signing with one fixed identity makes "Always Allow" stick.
#
# What this touches: adds one certificate + private key to your *login*
# keychain and marks that certificate trusted for code signing, for your user
# only. Nothing is added to the System keychain and nothing needs sudo — macOS
# will ask for your login password once.
#
# Run once:  Scripts/make_signing_identity.sh
# Undo:      open Keychain Access, login keychain, delete "PUPSISPortal Local
#            Signing" (both the certificate and its key).
set -e

CN="PUPSISPortal Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$CN"; then
  echo "Identity \"$CN\" already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Generating a self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  >/dev/null 2>&1

openssl pkcs12 -export -out "$TMP/identity.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass: >/dev/null 2>&1

# -T limits use of the private key to codesign rather than any binary.
echo "Importing into the login keychain (macOS may ask for your password)..."
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "" -T /usr/bin/codesign

echo "Marking it trusted for code signing (user domain only)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
echo "Done. Scripts/make_mac_app.sh will pick this up automatically."
echo "The first launch after this still prompts once — click Always Allow,"
echo "and it should stay quiet from then on."
