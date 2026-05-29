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
scripts/make-icns.sh "/Users/huiyunlee/Pictures/pfp/whisker.png" "$APP/Contents/Resources/AppIcon.icns"

# Info.plist
cp Info.plist "$APP/Contents/Info.plist"

# Menu-bar icon source. The app loads this via Bundle.main (Contents/Resources) in the
# packaged build — this is what resolves in the signed, drag-installed .app. (Bundle.module
# can't be used here: its generated accessor looks for the resource bundle at the .app root,
# and macOS forbids non-Contents items at the bundle root, which breaks code signing.)
cp Sources/Whisker/Resources/whisker.png "$APP/Contents/Resources/whisker.png"

# Also include the SwiftPM resource bundle under Contents/Resources (the canonical,
# code-signable location). Harmless if Bundle.module never reads it.
RES_BUNDLE=".build/release/Whisker_Whisker.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

# Ad-hoc codesign so it launches without "damaged" errors on the same machine.
# Surface failures instead of hiding them — a broken signature is worth knowing about.
if ! codesign --force --deep --sign - "$APP"; then
  echo "WARNING: codesign failed (see error above); the app will still run after right-click→Open."
fi

# Assemble DMG staging with an Applications symlink for drag-install.
STAGING="build/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Whisker" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Wrote $DMG and $APP"
