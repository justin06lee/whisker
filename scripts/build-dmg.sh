#!/bin/bash
# Builds Whisker.app (release) and packages it into a drag-to-Applications DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building release…"
swift build -c release

BIN=".build/release/Whisker"
APP="build/Whisker.app"
DMG="build/Whisker.dmg"

rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Executable
cp "$BIN" "$APP/Contents/MacOS/Whisker"

# Icon
scripts/make-icns.sh "Sources/Whisker/Resources/appicon.png" "$APP/Contents/Resources/AppIcon.icns"

# Info.plist
cp Info.plist "$APP/Contents/Info.plist"

# Icon sources. The app loads these via Bundle.main (Contents/Resources) in the
# packaged build — this is what resolves in the signed, drag-installed .app. (Bundle.module
# can't be used here: its generated accessor looks for the resource bundle at the .app root,
# and macOS forbids non-Contents items at the bundle root, which breaks code signing.)
# menubar.png = transparent status-item icon; appicon.png = Dock/onboarding icon.
cp Sources/Whisker/Resources/menubar.png "$APP/Contents/Resources/menubar.png"
cp Sources/Whisker/Resources/appicon.png "$APP/Contents/Resources/appicon.png"

# Also include the SwiftPM resource bundle under Contents/Resources (the canonical,
# code-signable location). Harmless if Bundle.module never reads it.
RES_BUNDLE=".build/release/Whisker_Whisker.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

# Code signing. Prefer a STABLE self-signed identity so macOS keeps the Accessibility
# grant across rebuilds; fall back to ad-hoc (which forces a re-grant every build).
# See scripts/make-signing-cert.sh.
# Check WITHOUT -v: a self-signed cert is usable for signing even though it lists as
# "not trusted" (which only affects Gatekeeper verification, not signing or TCC matching).
SIGN_ID="Whisker Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "Signing with stable identity '$SIGN_ID' (Accessibility grant persists across rebuilds)…"
  if ! codesign --force --deep --sign "$SIGN_ID" "$APP"; then
    echo "WARNING: codesign with '$SIGN_ID' failed (see error above)."
  fi
else
  echo "No stable signing identity ('$SIGN_ID') found."
  echo "  -> Run scripts/make-signing-cert.sh ONCE to stop macOS re-asking for Accessibility every build."
  echo "Falling back to ad-hoc signing (Accessibility must be re-granted after each rebuild)."
  if ! codesign --force --deep --sign - "$APP"; then
    echo "WARNING: codesign failed (see error above); the app will still run after right-click→Open."
  fi
fi

# Assemble DMG staging with an Applications symlink for drag-install.
STAGING="build/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Whisker" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Wrote $DMG and $APP"
