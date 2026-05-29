#!/bin/bash
# Generates AppIcon.icns from a source PNG. Usage: scripts/make-icns.sh <src.png> <out.icns>
set -euo pipefail
SRC="${1:-Sources/Whisker/Resources/appicon.png}"
OUT="${2:-build/AppIcon.icns}"
WORK="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$WORK" "$(dirname "$OUT")"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size"      "$SRC" --out "$WORK/icon_${size}x${size}.png"   >/dev/null
  dbl=$((size*2))
  sips -z "$dbl" "$dbl"        "$SRC" --out "$WORK/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK" -o "$OUT"
echo "Wrote $OUT"
