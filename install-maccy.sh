#!/usr/bin/env bash
set -euo pipefail

[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"

brew install --cask maccy
