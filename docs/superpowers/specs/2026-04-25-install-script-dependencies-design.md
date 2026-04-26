# Install Script Dependencies — Design

Date: 2026-04-25 (revised after pivot from custom bash dispatcher to Make)

## Goal

Decompose the existing `install-claude-code.sh` into a set of single-purpose install scripts and a `Makefile` that declares the dependencies between them. Re-running `make <thing>` must be cheap and side-effect-free when everything is already installed.

The repo will grow as more macOS tools are added (next up: Maccy).

## Why Make

An earlier iteration of this design built a bash-only system: each install script defined `verify`/`install` subcommands, a `lib/common.sh` provided a `require` helper that ran sibling scripts as subprocesses, and a `dispatch` case statement was duplicated at the bottom of every script.

That worked but was bash-heavy: `set -e` interactions with `||` chains, sourcing-vs-subprocess decisions to avoid function-name collisions, dispatch boilerplate per script, and a small but real "must know bash conventions" tax for anyone reading the code.

Make replaces almost all of that machinery:
- Dependencies are declared once, in one file (the Makefile), as plain `target: deps` lines.
- Make automatically dedupes — if two targets share a dependency, the dependency runs once.
- The "skip if already installed" check is one inline shell expression per recipe (e.g. `@command -v brew >/dev/null 2>&1 || bash install-homebrew.sh`).
- Each install script becomes 2–10 lines of "do the install" — no dispatch, no `require`, no shared library.

Make ships on macOS via the Xcode Command Line Tools. `/usr/bin/make` is a stub on a CLT-less machine that triggers the CLT GUI installer prompt automatically when first invoked, which means the chicken-and-egg of "need CLT to run make" self-resolves: the user runs `make claude-code`, gets the CLT installer prompt, clicks through, re-runs `make claude-code`, and the chain proceeds.

## Non-goals

- Version pinning or upgrade detection. Recipes check "is this installed at all," not "is the right version installed."
- A top-level `make all` that installs every tool. Each tool is its own target; the user invokes the ones they want.
- Cross-shell support beyond bash. The user has chsh'd to bash; zsh handling is out of scope.

## Layout

```
mac-setup/
├── Makefile
├── install-xcode-clt.sh
├── install-bash-shell.sh
├── install-bash-init.sh
├── install-homebrew.sh
├── install-claude-code.sh
├── install-maccy.sh
└── README.md
```

No `lib/` directory; no shared shell library. Each install script is fully self-contained.

## The Makefile

```makefile
.PHONY: claude-code maccy homebrew bash-init bash-shell xcode-clt

xcode-clt:
	@xcode-select -p >/dev/null 2>&1 || bash install-xcode-clt.sh

bash-shell:
	@[ "$$(dscl . -read $$HOME UserShell | awk '{print $$2}')" = "/bin/bash" ] \
		|| bash install-bash-shell.sh

bash-init: bash-shell
	@bash install-bash-init.sh

homebrew: xcode-clt bash-init
	@command -v brew >/dev/null 2>&1 || bash install-homebrew.sh

claude-code: homebrew
	@command -v claude >/dev/null 2>&1 || bash install-claude-code.sh

maccy: homebrew
	@[ -d /Applications/Maccy.app ] || bash install-maccy.sh
```

Notes on the recipe pattern:
- `@` suppresses command echo so the user only sees the install script's own output when something runs.
- `$$` escapes `$` for make's two-pass interpolation; the shell sees `$(...)` and `$VAR`.
- The inline guard (`<check> || bash install-<name>.sh`) is the "skip if installed" optimization. If the check passes, the install script is never invoked.
- `bash-init` has no inline guard because its check is multi-part (.bashrc exists, .bash_profile sources it, .zprofile/.zshrc clean of stale brew lines). The script itself is internally idempotent — each mutation is guarded — so it's safe to invoke unconditionally.

## Dependency graph

```
xcode-clt ───┐
             ├──► homebrew ──► claude-code
bash-shell ──► bash-init ──┘            └─► maccy
```

This graph is encoded directly in the Makefile's `target: deps` lines; no graph-walker is needed.

- `xcode-clt`: required by `homebrew` (the brew installer needs it).
- `bash-shell`: sets login shell to `/bin/bash`; required by `bash-init`.
- `bash-init`: sets up `~/.bashrc`/`~/.bash_profile` plumbing and cleans stale brew lines from zsh init files; required by `homebrew` so brew's shellenv line is written once to `.bashrc` and seen by all shell types.
- `homebrew`: required by `claude-code` and `maccy` (and any future cask install).

## Per-script behavior

Each script is invoked when its Makefile guard fails. Scripts may assume their dependencies have run (because make ran them first). Scripts trust the underlying tools to be safely re-invokable: `brew install` of an already-installed package is a no-op, `dscl . -change` to the current shell is a no-op, etc. For mutations that aren't naturally idempotent (file edits in `bash-init`), each mutation has its own guard inside the script.

### `install-xcode-clt.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
xcode-select --install || true
echo "Finish the GUI installer, then re-run make." >&2
exit 1
```

Triggers the GUI installer and bails non-zero so make halts. The user re-runs `make <whatever>` after the GUI completes.

### `install-bash-shell.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cur="$(dscl . -read "$HOME" UserShell | awk '{print $2}')"
sudo dscl . -change "$HOME" UserShell "$cur" /bin/bash
```

Uses `sudo dscl` rather than `chsh -s` so the user enters their sudo password once for the whole chain — `homebrew`'s install also uses sudo within the same minute, and sudo's session cache covers both calls.

### `install-bash-init.sh`

```bash
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
```

Every mutation is guarded. Safe to invoke unconditionally.

The `.zprofile`/`.zshrc` cleanup removes stale `eval "$(... brew shellenv)"` lines left by the previous version of `install-claude-code.sh`. After the user chsh'd to bash, those zsh files are no longer read, but the lines linger; this script removes them.

### `install-homebrew.sh`

The bulk of the original `install-claude-code.sh`'s logic, plus a one-line append to `~/.bashrc` instead of `~/.zprofile`.

```bash
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
```

### `install-claude-code.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
brew install --cask claude-code
```

Make's `homebrew` dependency guarantees brew is installed by the time this script runs. `brew` may not be on PATH yet in this shell session if homebrew was just installed, so the script may need a `eval "$(/opt/homebrew/bin/brew shellenv)"` prelude to find brew. Two options:
- Make the recipe itself eval brew shellenv before calling the script (clutters the Makefile).
- Have each cask install script eval brew shellenv at the top.

We'll use the second: each cask install script begins with a brew-on-PATH eval.

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"
brew install --cask claude-code
```

(The two `eval` lines are mutually exclusive on any given machine; only one path will exist.)

### `install-maccy.sh`

Same shape as `install-claude-code.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"
brew install --cask maccy
```

## Idempotency model

Two layers, on purpose:

1. **Makefile guards** — fast-path "already installed?" checks per target. If the guard passes, the script is never invoked. This is what gives us `make claude-code` returning instantly when claude is already there.
2. **Internal idempotency** — scripts that mutate state (`install-bash-init.sh` in particular) guard each mutation so direct invocation (`bash install-bash-init.sh`) is also safe. The cask install scripts trust `brew install` to no-op on already-installed packages.

If you bypass `make` and run a script directly, the worst case is an extra round-trip to brew (which itself short-circuits). No script causes harm when re-run.

## Failure modes

A non-zero exit from any script halts make. The user fixes whatever's wrong and re-runs `make <whatever>` — the deps that already succeeded are skipped by their guards, and make resumes at the failed step.

There's no distinction between "human action required" (CLT GUI installer in progress) and "real error" (brew install hit a network failure). At this scale, that's an acceptable simplification.

## Bootstrap ordering

`make` itself is provided by `/usr/bin/make`, which is a stub on macOS that triggers the Xcode Command Line Tools GUI installer when invoked on a CLT-less system. So:

1. User runs `make claude-code` on a fresh Mac.
2. macOS prompts for CLT install (because `make` itself isn't there until CLT is).
3. User clicks through the installer.
4. User re-runs `make claude-code`. Make is now available; the dependency chain proceeds.
5. The Makefile's `xcode-clt` target's guard now passes (`xcode-select -p` succeeds), so `install-xcode-clt.sh` is never invoked.

The `xcode-clt` target and its install script remain useful: future tools that need CLT directly (without going through brew) can declare the dep, and the script handles the rare case where someone tries to bootstrap without going through `make` first.
