#!/bin/bash
# assets/AppIcon.svg -> assets/AppIcon.icns. Only needed after editing the SVG (brew install librsvg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  rsvg-convert -w "$s" -h "$s" "$ROOT/assets/AppIcon.svg" -o "$SET/icon_${s}x${s}.png"
  rsvg-convert -w $((s * 2)) -h $((s * 2)) "$ROOT/assets/AppIcon.svg" -o "$SET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$SET" -o "$ROOT/assets/AppIcon.icns"
rm -rf "$(dirname "$SET")"
echo "$ROOT/assets/AppIcon.icns"
