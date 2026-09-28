#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/UIBoard.app"
if pgrep -x UIBoard >/dev/null; then
  echo "abort: UIBoard is running; quit it first (unexported annotations would be lost)" >&2
  exit 1
fi
"$ROOT/scripts/bundle.sh" >/dev/null
rm -rf "$DEST"
ditto "$ROOT/build/UIBoard.app" "$DEST"
echo "$DEST"
