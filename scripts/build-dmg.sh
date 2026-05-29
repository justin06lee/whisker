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

# ---- Styled DMG ----
STAGING="build/dmg-staging"
RW_DMG="build/Whisker-rw.dmg"
VOL="Whisker"
rm -rf "$STAGING" "$RW_DMG" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Read-write DMG we can style, sized with headroom.
hdiutil create -volname "$VOL" -srcfolder "$STAGING" -fs HFS+ \
  -format UDRW -size 200m -ov "$RW_DMG"

# Mount it.
MOUNT="/Volumes/$VOL"
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | grep -E '^/dev/' | head -1 | awk '{print $1}')"

style_ok=1
if [ -n "${DEV:-}" ] && [ -d "$MOUNT" ]; then
  # Volume icon = app icon (shows the whisker icon on the mounted disk).
  if cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns" 2>/dev/null; then
    SetFile -a C "$MOUNT" 2>/dev/null || true
  fi

  # Finder layout via AppleScript, bounded by a 25s alarm so it can never hang the build.
  perl -e 'alarm 25; exec @ARGV' osascript <<'APPLESCRIPT' >/dev/null 2>&1 || style_ok=0
tell application "Finder"
  tell disk "Whisker"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 128
    set text size of vo to 12
    set position of item "Whisker.app" of container window to {160, 200}
    set position of item "Applications" of container window to {460, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
  [ "$style_ok" = "0" ] && echo "DMG styling skipped (Finder automation unavailable) — shipping a plain layout."
  sync
  hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true
else
  echo "Could not mount RW DMG for styling — shipping a plain layout."
fi

# Convert to compressed read-only final DMG.
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG"
rm -f "$RW_DMG"
rm -rf "$STAGING"
echo "Wrote $DMG and $APP"
