#!/usr/bin/env bash
# Draw the app icon (Scripts/make_icon.swift) and build Resources/AppIcon/SkillsPack.icns from it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/Resources/AppIcon"
TMP=$(mktemp -d)
mkdir -p "$OUT" "$ROOT/docs/assets"
swift "$ROOT/Scripts/make_icon.swift" "$OUT/icon-1024.png" 1024
ICONSET="$TMP/SkillsPack.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$OUT/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$OUT/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/SkillsPack.icns"
sips -z 256 256 "$OUT/icon-1024.png" --out "$ROOT/docs/assets/app-icon.png" >/dev/null
rm -rf "$TMP"
echo "wrote $OUT/SkillsPack.icns and docs/assets/app-icon.png"
