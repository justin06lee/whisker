#!/bin/bash
# Signs Whisker.app with a Developer ID certificate, notarizes the DMG with
# Apple, and staples the ticket — the step that lets other people download and
# open Whisker without right-click→Open.
#
# Prerequisites (one-time):
#   1. A paid Apple Developer account.
#   2. A "Developer ID Application" certificate in your login keychain
#      (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates, or developer.apple.com).
#   3. A notarytool keychain profile:
#        xcrun notarytool store-credentials whisker-notary \
#          --apple-id you@example.com --team-id TEAMID1234 --password <app-specific-password>
#
# Usage:
#   scripts/build-dmg.sh                                   # build first
#   SIGN_ID="Developer ID Application: Your Name (TEAMID1234)" scripts/notarize.sh
#
# Optional env:
#   NOTARY_PROFILE  notarytool keychain profile name (default: whisker-notary)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Whisker.app"
DMG="build/Whisker.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-whisker-notary}"

if [ -z "${SIGN_ID:-}" ]; then
  echo "ERROR: set SIGN_ID to your Developer ID Application identity, e.g."
  echo '  SIGN_ID="Developer ID Application: Your Name (TEAMID1234)" scripts/notarize.sh'
  exit 1
fi
[ -d "$APP" ] || { echo "ERROR: $APP not found — run scripts/build-dmg.sh first."; exit 1; }

echo "Re-signing $APP with '$SIGN_ID' (hardened runtime, required for notarization)…"
codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "Rebuilding DMG around the Developer-ID-signed app…"
rm -f "$DMG"
hdiutil create -volname Whisker -srcfolder "$APP" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "Submitting to Apple notary service (waits for the verdict)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling the notarization ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "Done: $DMG is notarized and staples offline. Gatekeeper will open it without warnings."
