# Install Script Dependencies — Design

Date: 2026-04-25

## Goal

Decompose the existing `install-claude-code.sh` into a small set of single-purpose install scripts that can declare dependencies on each other. Re-running any script (or any of its callers) must be cheap and side-effect-free when everything is already installed.

The repo will grow over time as more macOS tools are added (next up: Maccy). The design is for that growth, not just today's two scripts.

## Non-goals

- Version pinning or upgrade detection. `verify` answers "is this installed at all," not "is the right version installed."
- A top-level `install-everything.sh` orchestrator. Each install script is its own user-facing entry point. A manifest/orchestrator can be added later if the set grows large enough to warrant it.
- Cross-shell support beyond bash. The user has `chsh`'d to bash; zsh handling is stubbed in the shell-init helper but not implemented.

## Layout

```
mac-setup/
├── install-xcode-clt.sh
├── install-bash-shell.sh
├── install-bash-init.sh
├── install-homebrew.sh
├── install-claude-code.sh
├── install-maccy.sh
└── lib/
    └── common.sh
```

## Script contract

Every `install-<name>.sh` accepts a subcommand as its first argument:

| Subcommand | Behavior |
|---|---|
| `verify` | Cheap, side-effect-free check. Exits `0` if the thing is already installed/configured. Non-zero otherwise. |
| `install` | Performs the actual installation. May prompt for credentials or trigger GUI installers. Exits non-zero if a human action is required (caller halts; user re-runs after completing the action). |
| *(no arg)* | Runs `verify || install`. This is the user-facing default. |

Constraints:
- `verify` must not mutate state.
- `install` must be idempotent enough that re-running after a partial failure is safe.
- `install` may call `require <other>` for its dependencies; `verify` should not (a verified-installed thing implies its deps were satisfied at install time).

## Dependency graph

```
xcode-clt ───┐
             ├──► homebrew ──► claude-code
bash-shell ──► bash-init ──┘            └─► maccy
```

- `xcode-clt`: required by `homebrew` (brew bootstrap depends on the Xcode Command Line Tools)
- `bash-shell`: chsh's the user to `/bin/bash`; required by `bash-init`
- `bash-init`: ensures `~/.bashrc` exists and is sourced from `~/.bash_profile`; required by `homebrew` (so brew's shellenv line can be written once to `.bashrc` and seen by all shell types)
- `homebrew`: required by `claude-code` and `maccy` (and any future cask install)

## `lib/common.sh`

Provides:

- `log "msg"` — colored info line (existing helper, lifted from current script)
- `have <cmd>` — `command -v <cmd> >/dev/null 2>&1` (existing helper)
- `require <name>` — runs `bash install-<name>.sh verify`; if it fails, runs `bash install-<name>.sh install`. Subprocess (not source) to keep function namespaces clean across scripts.
- `add_shell_init_line "<line>"` — idempotent `grep -F`-then-append to `~/.bashrc` (bash case). Cases for other shells (`zsh`) error out with a "add this manually" message until implemented.
- `load_brew_env` — `eval "$(/opt/homebrew/bin/brew shellenv)"` with `/usr/local` fallback, for callers that need brew on PATH in the current shell after `require homebrew`.

`require` resolves dependency scripts relative to the directory of the calling script (siblings on disk).

## Per-script behavior

### `install-xcode-clt.sh`

- `verify`: `xcode-select -p >/dev/null 2>&1`
- `install`: triggers `xcode-select --install` (GUI installer), prints "complete the installer, then re-run" and exits non-zero. The `require` chain halts; the user re-runs after the GUI completes.

### `install-bash-shell.sh`

- `verify`: `[[ "$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}')" == "/bin/bash" ]]`. `dscl` is used (not `$SHELL`) because `$SHELL` doesn't update mid-session after `chsh`.
- `install`: `chsh -s /bin/bash`. Prompts for the user's login password (separate from sudo). No `/etc/shells` edit needed — `/bin/bash` is already listed by default on macOS.

### `install-bash-init.sh`

Depends on: `bash-shell`.

- `verify`: `~/.bashrc` exists AND `~/.bash_profile` contains a line that sources `~/.bashrc`.
- `install`:
  - `touch ~/.bashrc` if missing
  - if `~/.bash_profile` doesn't already source `.bashrc`, append `[ -f ~/.bashrc ] && . ~/.bashrc`

### `install-homebrew.sh`

Depends on: `xcode-clt`, `bash-init`.

- `verify`: `have brew || [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ]]`
- `install`:
  - `require xcode-clt`
  - `require bash-init`
  - sudo prime + keepalive (lifted from current script)
  - `NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  - resolve `BREW_PREFIX` to `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel) by checking which `brew` binary exists
  - after the install succeeds, call `add_shell_init_line "eval \"\$($BREW_PREFIX/bin/brew shellenv)\""` — the line is written to `.bashrc` and picked up by both login and interactive shells via the bash-init plumbing.

### `install-claude-code.sh`

Depends on: `homebrew`.

- `verify`: `have claude`
- `install`:
  - `require homebrew`
  - `load_brew_env`
  - `brew install --cask claude-code`

### `install-maccy.sh`

Depends on: `homebrew`.

- `verify`: `[[ -d /Applications/Maccy.app ]]` (Maccy is an app bundle, not a CLI — `have` won't work)
- `install`:
  - `require homebrew`
  - `load_brew_env`
  - `brew install --cask maccy`

## Idempotency

"Don't re-run when already installed" is enforced by each script's `verify`, not by marker files. Marker files lie when the user uninstalls something out of band; verify always reflects current reality.

`require` does not re-verify after install. It trusts the install's exit code. If a verify-after-install step is wanted later (paranoid mode), it's a one-line addition to `require` — no contract change.

## Failure modes

All non-zero exits are treated equally: caller halts, user re-runs. There is no distinction between "human action required" (CLT GUI, chsh password failure) and "real error" (network failure during brew install). At this scale, that's an acceptable simplification. If retry-vs-bail logic becomes valuable, the contract can grow specific exit codes without breaking existing scripts.

## Shell init scope

`add_shell_init_line` writes to `~/.bashrc` only. `bash-init` guarantees `.bash_profile` sources `.bashrc`, so both login and non-login interactive bash shells see the line. This single source of truth covers Terminal.app, iTerm2, VSCode integrated terminals, and tmux panes uniformly.

`zsh` and other shells fall through to an error path in `add_shell_init_line` with instructions to add the line manually. Adding zsh support later is one `case` arm plus a parallel `install-zsh-init.sh`; not in scope today.
