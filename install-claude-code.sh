#!/usr/bin/env bash
# Install the Claude Code CLI on a fresh macOS.
# Safe to re-run: each step is skipped if already done.

set -euo pipefail

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is for macOS." >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as your normal user, not with sudo. Homebrew refuses to install as root." >&2
  exit 1
fi

# 1. Xcode Command Line Tools — required by Homebrew.
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (a GUI prompt will appear)…"
  xcode-select --install || true
  echo "Finish the installer, then re-run this script."
  exit 0
else
  log "Xcode Command Line Tools already installed."
fi

# 2. Homebrew.
if ! have brew && [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
  log "Priming sudo (Homebrew's non-interactive installer needs cached credentials)…"
  sudo -v
  # Keep sudo alive while the installer runs.
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

  log "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  trap - EXIT
else
  log "Homebrew already installed."
fi

# Make brew available in this shell and in future shells.
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_PREFIX=/opt/homebrew            # Apple Silicon
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_PREFIX=/usr/local               # Intel
else
  echo "Homebrew install did not produce a brew binary." >&2
  exit 1
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"

ZPROFILE="$HOME/.zprofile"
SHELLENV_LINE="eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
if ! grep -Fqs "$SHELLENV_LINE" "$ZPROFILE" 2>/dev/null; then
  log "Adding Homebrew to ${ZPROFILE}…"
  printf '\n%s\n' "$SHELLENV_LINE" >> "$ZPROFILE"
fi

# 3. Claude Code CLI.
if have claude; then
  log "claude already on PATH at: $(command -v claude)"
else
  log "Installing Claude Code via Homebrew cask…"
  brew install --cask claude-code
fi

log "Done. Open a new terminal and run:  claude --version"
