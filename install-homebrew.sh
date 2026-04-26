#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is for macOS." >&2
  exit 1
fi
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as your normal user, not with sudo. Homebrew refuses to install as root." >&2
  exit 1
fi

sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null || true' EXIT

NONINTERACTIVE=1 /bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

kill "$KEEPALIVE" 2>/dev/null || true
trap - EXIT

if [[ -x /opt/homebrew/bin/brew ]]; then
  PREFIX=/opt/homebrew
elif [[ -x /usr/local/bin/brew ]]; then
  PREFIX=/usr/local
else
  echo "Homebrew install did not produce a brew binary." >&2
  exit 1
fi

LINE="eval \"\$($PREFIX/bin/brew shellenv)\""
grep -Fqs "$LINE" "$HOME/.bashrc" 2>/dev/null \
  || printf '\n%s\n' "$LINE" >> "$HOME/.bashrc"
