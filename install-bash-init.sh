#!/usr/bin/env bash
set -euo pipefail

BASHRC="$HOME/.bashrc"
BASH_PROFILE="$HOME/.bash_profile"
SOURCE_LINE='[ -f ~/.bashrc ] && . ~/.bashrc'

[ -f "$BASHRC" ] || touch "$BASHRC"

if ! grep -Fqs "$SOURCE_LINE" "$BASH_PROFILE" 2>/dev/null; then
  printf '\n%s\n' "$SOURCE_LINE" >> "$BASH_PROFILE"
fi

for f in "$HOME/.zprofile" "$HOME/.zshrc"; do
  if [ -f "$f" ] && grep -qs 'brew shellenv' "$f"; then
    sed -i '' '/brew shellenv/d' "$f"
  fi
done
