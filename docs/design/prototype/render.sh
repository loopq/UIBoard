#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BOARDS=(
  "A editor-empty 1280,820"
  "B editor-working 1280,820"
  "C editor-working-dark 1280,820"
  "D device-menu 1280,820"
  "E export-sheet 1280,820"
  "F replace-alert 1280,820"
  "G history 900,640"
  "H settings 560,260"
)
for b in "${BOARDS[@]}"; do
  read -r id name size <<<"$b"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size="$size" --screenshot="$DIR/$id-$name.png" \
    "file://$DIR/uiboard-prototype.html#$id" 2>/dev/null
done
ls -1 "$DIR"/*.png
