#!/usr/bin/env bash
set -euo pipefail

cur="$(dscl . -read "$HOME" UserShell | awk '{print $2}')"
sudo dscl . -change "$HOME" UserShell "$cur" /bin/bash
