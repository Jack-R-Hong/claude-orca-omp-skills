#!/usr/bin/env bash
# Symlinks every skill in skills/ into ~/.claude/skills so edits to the repo take effect immediately.
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$dest"

for skill in "$repo"/skills/*/; do
  name="$(basename "$skill")"
  target="$dest/$name"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "skip $name: $target exists and is not a symlink"
    continue
  fi
  ln -sfn "${skill%/}" "$target"
  echo "linked $name -> ${skill%/}"
done
