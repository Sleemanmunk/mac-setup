# Install Script Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose `install-claude-code.sh` into single-purpose, dependency-aware install scripts (xcode-clt, bash-shell, bash-init, homebrew, claude-code, maccy) sharing a small `lib/common.sh` library.

**Architecture:** Every `install-<name>.sh` script accepts `verify`/`install` subcommands (default: `verify || install`). A `require <name>` helper in `lib/common.sh` invokes a sibling script's `verify`, falling through to `install` if it fails. Scripts are invoked from the project root; each script's first non-shebang lines source `./lib/common.sh`.

**Tech Stack:** bash 3.2 (system bash on macOS), `dscl` for shell-database changes, Homebrew for the actual installs.

**Spec:** `docs/superpowers/specs/2026-04-25-install-script-dependencies-design.md`

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/common.sh` | Sourced helpers: `log`, `have`, `require`, `add_shell_init_line`, `load_brew_env` |
| `install-xcode-clt.sh` | Verify/install Xcode Command Line Tools (GUI installer if missing) |
| `install-bash-shell.sh` | Verify/install login shell == `/bin/bash` (via `sudo dscl . -change`) |
| `install-bash-init.sh` | Verify/install bash init plumbing + cleanup of stale brew lines in `.zprofile`/`.zshrc` |
| `install-homebrew.sh` | Verify/install Homebrew; writes shellenv line to `.bashrc` via the helper |
| `install-claude-code.sh` | Thin wrapper: `require homebrew && brew install --cask claude-code` (rewrites the existing monolithic script) |
| `install-maccy.sh` | Same shape as claude-code, but for Maccy |
| `README.md` | Already updated to document "run from project root" expectation |

All `install-*.sh` files use the same skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

verify() { ...; }
install_step() { ...; }

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

The dispatch block is identical across every script — only `verify` and `install_step` differ.

---

### Task 1: Create `lib/common.sh`

**Files:**
- Create: `lib/common.sh`

- [ ] **Step 1: Create the file**

```bash
# Sourced by every install-*.sh script.
# The caller is expected to run from the project root (siblings on disk).

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Run a sibling install script's verify; if it fails, run its install.
# Subprocess (not source) so each script gets a clean function namespace.
require() {
  local name="$1"
  bash "./install-$name.sh" verify >/dev/null 2>&1 || bash "./install-$name.sh" install
}

# Append a line to the user's shell init file if not already present.
# Detects the shell authoritatively via dscl (since $SHELL doesn't update
# mid-session after a chsh / dscl change).
add_shell_init_line() {
  local line="$1"
  local current_shell file
  current_shell="$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}')"
  case "$(basename "$current_shell")" in
    bash) file="$HOME/.bashrc" ;;
    *)
      echo "Unknown shell ($current_shell); add this manually: $line" >&2
      return 1
      ;;
  esac
  if ! grep -Fqs "$line" "$file" 2>/dev/null; then
    log "Adding to ${file}: $line"
    printf '\n%s\n' "$line" >> "$file"
  fi
}

# Make brew available on PATH in the current shell.
load_brew_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "load_brew_env: brew not found in /opt/homebrew or /usr/local" >&2
    return 1
  fi
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n lib/common.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add lib/common.sh
git commit -m "Add lib/common.sh with require/log/have/add_shell_init_line/load_brew_env"
```

---

### Task 2: Create `install-xcode-clt.sh`

**Files:**
- Create: `install-xcode-clt.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

verify() {
  xcode-select -p >/dev/null 2>&1
}

install_step() {
  log "Installing Xcode Command Line Tools (a GUI prompt will appear)…"
  xcode-select --install || true
  echo "Finish the installer, then re-run this script." >&2
  exit 1
}

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-xcode-clt.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run verify (CLT is already installed on this machine)**

Run: `bash install-xcode-clt.sh verify; echo "exit=$?"`
Expected: `exit=0`

- [ ] **Step 4: Commit**

```bash
git add install-xcode-clt.sh
git commit -m "Add install-xcode-clt.sh"
```

---

### Task 3: Create `install-bash-shell.sh`

**Files:**
- Create: `install-bash-shell.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

current_shell() {
  dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}'
}

verify() {
  [[ "$(current_shell)" == "/bin/bash" ]]
}

install_step() {
  local cur
  cur="$(current_shell)"
  log "Setting login shell to /bin/bash (was: $cur)…"
  sudo dscl . -change "$HOME" UserShell "$cur" /bin/bash
}

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-bash-shell.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run verify (user already chsh'd to bash)**

Run: `bash install-bash-shell.sh verify; echo "exit=$?"`
Expected: `exit=0`

- [ ] **Step 4: Commit**

```bash
git add install-bash-shell.sh
git commit -m "Add install-bash-shell.sh"
```

---

### Task 4: Create `install-bash-init.sh`

**Files:**
- Create: `install-bash-init.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

BASH_PROFILE="$HOME/.bash_profile"
BASHRC="$HOME/.bashrc"
ZPROFILE="$HOME/.zprofile"
ZSHRC="$HOME/.zshrc"
SOURCE_BASHRC_LINE='[ -f ~/.bashrc ] && . ~/.bashrc'

bashrc_exists() { [[ -f "$BASHRC" ]]; }

bash_profile_sources_bashrc() {
  [[ -f "$BASH_PROFILE" ]] && grep -Fqs "$SOURCE_BASHRC_LINE" "$BASH_PROFILE"
}

zsh_init_clean() {
  local f
  for f in "$ZPROFILE" "$ZSHRC"; do
    [[ -f "$f" ]] || continue
    grep -qs 'brew shellenv' "$f" && return 1
  done
  return 0
}

verify() {
  bashrc_exists && bash_profile_sources_bashrc && zsh_init_clean
}

install_step() {
  require bash-shell

  if ! bashrc_exists; then
    log "Creating $BASHRC"
    touch "$BASHRC"
  fi

  if ! bash_profile_sources_bashrc; then
    log "Configuring $BASH_PROFILE to source $BASHRC"
    printf '\n%s\n' "$SOURCE_BASHRC_LINE" >> "$BASH_PROFILE"
  fi

  local f
  for f in "$ZPROFILE" "$ZSHRC"; do
    if [[ -f "$f" ]] && grep -qs 'brew shellenv' "$f"; then
      log "Removing stale brew shellenv line from $f"
      sed -i '' '/brew shellenv/d' "$f"
    fi
  done
}

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-bash-init.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run verify before any cleanup**

Run: `bash install-bash-init.sh verify; echo "exit=$?"`
Expected: `exit=1` if either the `.bash_profile` source line is missing OR `.zprofile` has the stale brew line from the previous version of `install-claude-code.sh`. Either condition is the reason this script exists.

(If the machine somehow already has the bash-init plumbing AND no stale zsh lines, verify will return 0; the rest of the integration check will still exercise this script via `require` in install-homebrew.)

- [ ] **Step 4: Commit**

```bash
git add install-bash-init.sh
git commit -m "Add install-bash-init.sh with stale .zprofile/.zshrc cleanup"
```

---

### Task 5: Create `install-homebrew.sh`

**Files:**
- Create: `install-homebrew.sh`

This is the bulk of the logic lifted out of the existing `install-claude-code.sh`.

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

verify() {
  have brew || [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ]]
}

install_step() {
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is for macOS." >&2
    exit 1
  fi
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "Run as your normal user, not with sudo. Homebrew refuses to install as root." >&2
    exit 1
  fi

  require xcode-clt
  require bash-init

  log "Priming sudo (Homebrew's non-interactive installer needs cached credentials)…"
  sudo -v
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  local keepalive_pid=$!
  trap 'kill "$keepalive_pid" 2>/dev/null || true' EXIT

  log "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  kill "$keepalive_pid" 2>/dev/null || true
  trap - EXIT

  local brew_prefix
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_prefix=/opt/homebrew
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_prefix=/usr/local
  else
    echo "Homebrew install did not produce a brew binary." >&2
    exit 1
  fi

  add_shell_init_line "eval \"\$($brew_prefix/bin/brew shellenv)\""
}

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-homebrew.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run verify (brew is already installed on this machine)**

Run: `bash install-homebrew.sh verify; echo "exit=$?"`
Expected: `exit=0`

- [ ] **Step 4: Commit**

```bash
git add install-homebrew.sh
git commit -m "Extract install-homebrew.sh from install-claude-code.sh"
```

---

### Task 6: Rewrite `install-claude-code.sh`

**Files:**
- Modify: `install-claude-code.sh` (full rewrite — replace all 76 lines with the thin version below)

- [ ] **Step 1: Replace the file contents**

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

verify() {
  have claude
}

install_step() {
  require homebrew
  load_brew_env
  log "Installing Claude Code via Homebrew cask…"
  brew install --cask claude-code
}

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-claude-code.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run verify (claude is already installed on this machine)**

Run: `bash install-claude-code.sh verify; echo "exit=$?"`
Expected: `exit=0`

- [ ] **Step 4: Commit**

```bash
git add install-claude-code.sh
git commit -m "Rewrite install-claude-code.sh as thin require-homebrew wrapper"
```

---

### Task 7: Create `install-maccy.sh`

**Files:**
- Create: `install-maccy.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -f ./lib/common.sh ]] || { echo "Run from the mac-setup project root." >&2; exit 1; }
source ./lib/common.sh

verify() {
  [[ -d /Applications/Maccy.app ]]
}

install_step() {
  require homebrew
  load_brew_env
  log "Installing Maccy via Homebrew cask…"
  brew install --cask maccy
}

case "${1:-default}" in
  verify)  verify ;;
  install) install_step ;;
  default) verify || install_step ;;
  *)       echo "Usage: $0 [verify|install]" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-maccy.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run verify (maccy is not yet installed on this machine)**

Run: `bash install-maccy.sh verify; echo "exit=$?"`
Expected: `exit=1` (Maccy.app does not exist in /Applications)

- [ ] **Step 4: Commit**

```bash
git add install-maccy.sh
git commit -m "Add install-maccy.sh"
```

---

### Task 8: Make install scripts executable

**Files:**
- Modify (perms only): `install-*.sh`

The existing `install-claude-code.sh` had its executable bit. Since we invoke via `bash install-foo.sh`, the bit isn't strictly required, but keeping it consistent across all install scripts is nice (and lets `./install-foo.sh` work too).

- [ ] **Step 1: chmod +x**

Run: `chmod +x install-*.sh`

- [ ] **Step 2: Verify**

Run: `ls -l install-*.sh`
Expected: every install script shows `-rwxr-xr-x` (or similar with the `x` bits set).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Make install-*.sh executable"
```

(`git add -A` is intentional here so mode bits get staged.)

---

### Task 9: Integration check

**Files:** none (read-only verification on disk).

The verify steps in earlier tasks confirmed each script's `verify` runs in isolation. This task exercises the dependency chain end-to-end and the actual cleanup work.

- [ ] **Step 1: Snapshot current shell-init state for comparison**

Run:
```bash
ls -l ~/.bash_profile ~/.bashrc ~/.zprofile ~/.zshrc 2>&1 || true
echo '---'
grep -H 'brew shellenv' ~/.zprofile ~/.zshrc 2>/dev/null || echo "(no brew shellenv lines found)"
echo '---'
grep -Fqs '[ -f ~/.bashrc ] && . ~/.bashrc' ~/.bash_profile && echo ".bash_profile sources .bashrc: yes" || echo ".bash_profile sources .bashrc: no"
```

Note the output. After running install-bash-init.sh below, expect:
- `.bashrc` to exist (created if missing)
- `.bash_profile` sources `.bashrc`: yes
- no `brew shellenv` lines in `.zprofile` or `.zshrc`

- [ ] **Step 2: Run install-bash-init directly to exercise the cleanup work**

Run: `bash install-bash-init.sh`
Expected: log lines describing whatever fixes are applied (creating `.bashrc`, adding source line to `.bash_profile`, removing stale brew line from `.zprofile`). On a machine with nothing to fix, no log output and exit 0.

- [ ] **Step 3: Verify install-bash-init now passes verify**

Run: `bash install-bash-init.sh verify; echo "exit=$?"`
Expected: `exit=0`

- [ ] **Step 4: Re-snapshot to confirm the cleanup happened**

Re-run the inspection from Step 1. Expect the output from Step 1's "expected" notes to match.

- [ ] **Step 5: Run install-claude-code (verify path)**

Run: `bash install-claude-code.sh`
Expected: `verify` passes (claude already installed) → script exits 0 with no install output. This confirms the rewritten script is wired up correctly.

- [ ] **Step 6: Optional — install Maccy for real**

This is the only step that performs a fresh install; gate it on user confirmation. Run only if the user wants to install Maccy now.

Run: `bash install-maccy.sh`
Expected:
- `require homebrew` → verify passes (brew already installed) → returns immediately
- `load_brew_env` runs
- `brew install --cask maccy` runs and installs Maccy
- Re-running `bash install-maccy.sh verify` afterwards exits 0

- [ ] **Step 7: Final state check**

Run: `git status; git log --oneline -10`
Expected: clean working tree; commits from tasks 1–8 present.

---

## Notes for the implementer

- **Don't run scripts from outside the project root.** The sanity check at the top of each script will refuse with a clear message; this is by design.
- **`set -e` interaction with `verify`:** the `verify || install_step` pattern is what keeps a non-zero exit from `verify` from killing the script. Don't restructure that line.
- **`require` is intentionally not re-verifying after install.** If the install's exit code is 0, we trust it. The spec discusses this as a future paranoid-mode option.
- **bash 3.2 compatibility:** macOS ships bash 3.2; avoid bash 4+ features (no associative arrays, no `${var,,}`, etc.). The code in this plan is 3.2-compatible.
- **macOS `sed -i ''`:** the empty-string argument after `-i` is required on macOS (BSD sed); GNU sed doesn't need it. Don't "fix" this to `sed -i`.
