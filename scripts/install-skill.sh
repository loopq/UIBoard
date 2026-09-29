#!/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)/skills/ui-review"
for dir in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  mkdir -p "$dir"
  dest="$dir/ui-review"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "abort: $dest is a real directory, remove it first" >&2
    exit 1
  fi
  ln -sfn "$SRC" "$dest"
  echo "linked $dest -> $SRC"
done
