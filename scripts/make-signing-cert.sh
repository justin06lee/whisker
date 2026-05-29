#!/bin/bash
# Creates a STABLE self-signed code-signing identity in the login keychain.
#
# Why: macOS Accessibility (TCC) ties a permission grant to the app's code-signing
# *designated requirement*. An ad-hoc signature (`codesign -s -`) has no stable
# identity — its requirement is the exact binary hash (cdhash), which changes on
# every rebuild — so macOS treats each new build as a different app and re-prompts
# for Accessibility every time. Signing every build with the SAME self-signed
# certificate keeps the requirement constant, so the grant persists across rebuilds.
#
# Run this ONCE. build-dmg.sh will then sign with this identity automatically.
# No Apple Developer account required.
set -euo pipefail

NAME="Whisker Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Note: list WITHOUT -v. A self-signed cert is usable by codesign even though it's
# "not trusted" (CSSMERR_TP_NOT_TRUSTED), so it won't appear under `-v` (valid-only).
# Trust matters for Gatekeeper verification, not for signing or TCC requirement-matching.
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Signing identity '$NAME' already exists — nothing to do."
  security find-identity -p codesigning | grep "$NAME"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Generating a self-signed code-signing certificate ('$NAME')…"
# Self-signed leaf cert with the codeSigning extended key usage.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
  -subj "/CN=$NAME" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "basicConstraints=critical,CA:false"

# Bundle key + cert into a PKCS#12 for import. OpenSSL 3 defaults to a PKCS12 MAC that
# macOS `security import` can't verify; use -legacy when available (LibreSSL/older openssl
# already produce a compatible file, and lack the flag).
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
  LEGACY="-legacy"
fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/whisker.p12" -name "$NAME" -passout pass:whisker

# Import into the login keychain and grant /usr/bin/codesign access to the private key.
security import "$TMP/whisker.p12" -k "$KEYCHAIN" -P whisker -T /usr/bin/codesign

# Try to whitelist codesign so it won't pop a GUI prompt on each sign. This needs the
# keychain password; if it can't run non-interactively, codesign will instead show a
# one-time "allow access" dialog on the first build — just click "Always Allow".
echo "Allowing codesign to use the new key (you may be asked for your login password)…"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 \
  || security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null 2>&1 \
  || echo "  (couldn't set partition list non-interactively — codesign may prompt once; click 'Always Allow')"

echo
echo "Done. New signing identity:"
security find-identity -p codesigning | grep "$NAME" || {
  echo "ERROR: identity not found after import." >&2
  exit 1
}
echo
echo "Next: run scripts/build-dmg.sh, install the app, and grant Accessibility ONCE."
echo "Future rebuilds keep the grant because the signature is now stable."
