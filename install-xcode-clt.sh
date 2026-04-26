#!/usr/bin/env bash
set -euo pipefail

xcode-select --install || true
echo "Finish the GUI installer, then re-run make." >&2
exit 1
