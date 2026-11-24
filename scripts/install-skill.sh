#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for skill in ui-review ui-bug; do
  SRC="$ROOT/skills/$skill"
  for dir in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
    mkdir -p "$dir"
    dest="$dir/$skill"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "abort: $dest is a real directory, remove it first" >&2
      exit 1
    fi
    ln -sfn "$SRC" "$dest"
    echo "linked $dest -> $SRC"
  done
done
