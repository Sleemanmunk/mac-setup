# Install Script Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose `install-claude-code.sh` into single-purpose install scripts orchestrated by a `Makefile` that declares dependencies between them.

**Architecture:** Make handles the dependency graph and the "skip if already installed" guards. Each install script is 2–10 lines of "do the install" with no shared library, no dispatch logic, and no inter-script dependencies in code.

**Tech Stack:** GNU/BSD-portable Make + bash 3.2-compatible scripts.

**Spec:** `docs/superpowers/specs/2026-04-25-install-script-dependencies-design.md`

**Pivot note:** An earlier version of this plan (commit `e0b73ec`) used a custom bash dispatcher with a `lib/common.sh` and a `require` helper. Task 1 of that plan (committing `lib/common.sh`) has already been merged at `0009271`. We're pivoting to the Makefile approach because the bash dispatcher imposed a "must know bash" tax (set-e interactions, source-vs-subprocess, function namespacing) that this design avoids entirely. Task 1 below removes `lib/common.sh`.

---

## File structure

| Path | Responsibility |
|---|---|
| `Makefile` | Dependency graph + per-target "skip if installed" guards |
| `install-xcode-clt.sh` | Trigger the CLT GUI installer and bail with a re-run message |
| `install-bash-shell.sh` | Set login shell to `/bin/bash` via `sudo dscl . -change` |
| `install-bash-init.sh` | Ensure `~/.bashrc` exists and is sourced from `~/.bash_profile`; clean stale brew lines from `.zprofile`/`.zshrc` |
| `install-homebrew.sh` | Run the Homebrew installer; append the brew shellenv line to `~/.bashrc` |
| `install-claude-code.sh` | `brew install --cask claude-code` (with brew-on-PATH prelude) |
| `install-maccy.sh` | `brew install --cask maccy` (with brew-on-PATH prelude) |
| `lib/common.sh` | **REMOVED** — no longer needed in the new design |

---

### Task 1: Remove `lib/common.sh`

**Files:**
- Delete: `lib/common.sh`
- Delete: `lib/` (becomes empty)

The file was created in commit `0009271` as part of the previous bash-dispatcher design. The Makefile-based design has no use for it.

- [ ] **Step 1: Remove the file and its directory**

```bash
rm lib/common.sh
rmdir lib
```

- [ ] **Step 2: Confirm removal**

Run: `ls lib 2>&1 || echo "lib/ removed"`
Expected: `ls: lib: No such file or directory` (or equivalent), followed by `lib/ removed`

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Remove lib/common.sh; pivot to Makefile-orchestrated install"
```

(`git add -A` stages the deletion.)

---

### Task 2: Create `Makefile`

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create the file**

The file uses **TAB** indentation for recipe lines (not spaces — Make is strict on this).

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

- [ ] **Step 2: Verify TAB indentation**

Run: `cat -A Makefile | grep -E '^[\^ ]' | head -5`
Expected: each recipe line starts with `^I` (the visible representation of a TAB). If you see leading spaces, the Makefile is broken — re-create it with tabs.

Alternative check: `awk '/^[^.#]/ && NR>1 && /^ /' Makefile`
Expected: no output (no recipe lines start with a space).

- [ ] **Step 3: Dry-run test**

Run: `make -n claude-code`
Expected: prints the recipes for `xcode-clt`, `bash-init` (which depends on `bash-shell`), `homebrew`, and `claude-code` in dependency order. No errors about missing targets or syntax.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "Add Makefile for install-script orchestration"
```

---

### Task 3: Create `install-xcode-clt.sh`

**Files:**
- Create: `install-xcode-clt.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail

xcode-select --install || true
echo "Finish the GUI installer, then re-run make." >&2
exit 1
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-xcode-clt.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add install-xcode-clt.sh
git commit -m "Add install-xcode-clt.sh"
```

---

### Task 4: Create `install-bash-shell.sh`

**Files:**
- Create: `install-bash-shell.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail

cur="$(dscl . -read "$HOME" UserShell | awk '{print $2}')"
sudo dscl . -change "$HOME" UserShell "$cur" /bin/bash
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-bash-shell.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add install-bash-shell.sh
git commit -m "Add install-bash-shell.sh"
```

---

### Task 5: Create `install-bash-init.sh`

**Files:**
- Create: `install-bash-init.sh`

- [ ] **Step 1: Create the file**

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

Note the `sed -i ''` — the empty-string argument after `-i` is required on macOS (BSD sed). Don't "fix" it to `sed -i`.

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-bash-init.sh`
Expected: no output, exit 0

- [ ] **Step 3: Run the script (it's idempotent and may do useful work on this machine)**

Run: `bash install-bash-init.sh`
Expected: exit 0. May produce no output (if everything is already in order) or silently mutate `~/.bash_profile` / `~/.zprofile` / `~/.zshrc` to fix issues.

- [ ] **Step 4: Verify the post-state**

Run:
```bash
grep -F '[ -f ~/.bashrc ] && . ~/.bashrc' ~/.bash_profile && echo "bash_profile sources bashrc: OK"
grep -qs 'brew shellenv' ~/.zprofile ~/.zshrc 2>/dev/null && echo "STALE BREW LINES STILL PRESENT" || echo "zsh init clean: OK"
```
Expected: both lines print "OK" (no "STALE BREW LINES" message).

- [ ] **Step 5: Run the script again to confirm idempotency**

Run: `bash install-bash-init.sh`
Expected: exit 0, no further mutations (no new lines appended to `.bash_profile`).

Verify: `wc -l ~/.bash_profile` before and after; line count unchanged on the second run.

- [ ] **Step 6: Commit**

```bash
git add install-bash-init.sh
git commit -m "Add install-bash-init.sh with stale .zprofile/.zshrc cleanup"
```

---

### Task 6: Create `install-homebrew.sh`

**Files:**
- Create: `install-homebrew.sh`

This is the bulk of the original `install-claude-code.sh`'s logic.

- [ ] **Step 1: Create the file**

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

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-homebrew.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add install-homebrew.sh
git commit -m "Extract install-homebrew.sh from install-claude-code.sh"
```

---

### Task 7: Rewrite `install-claude-code.sh`

**Files:**
- Modify: `install-claude-code.sh` (full rewrite — replace all 76 lines with the thin version below)

- [ ] **Step 1: Replace the file contents**

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"

brew install --cask claude-code
```

The two `eval` lines are mutually exclusive on any given machine; only one path will exist. This makes `brew` available on PATH for the install command, regardless of whether the calling shell already has the shellenv eval'd.

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-claude-code.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add install-claude-code.sh
git commit -m "Rewrite install-claude-code.sh as thin brew install wrapper"
```

---

### Task 8: Create `install-maccy.sh`

**Files:**
- Create: `install-maccy.sh`

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"

brew install --cask maccy
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n install-maccy.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add install-maccy.sh
git commit -m "Add install-maccy.sh"
```

---

### Task 9: Update README

**Files:**
- Modify: `README.md`

The current README says "Run scripts from the project root" with a `bash install-claude-code.sh` example. Update to point at `make`.

- [ ] **Step 1: Replace `README.md` with**

```markdown
# mac-setup

Install scripts for setting up a fresh macOS machine, orchestrated by Make.

## Usage

```bash
make claude-code   # install Claude Code (and its dependencies)
make maccy         # install Maccy
```

Each target's dependencies are installed automatically. Re-running a target is cheap when the underlying tool is already installed.

## On a fresh Mac

The first `make` invocation on a Mac without the Xcode Command Line Tools will trigger the GUI installer for the CLT (because `make` itself is provided by the CLT). Click through the installer, then re-run your `make` command.
\```

```

(Note: the inner triple-backticks for the bash code block need to be regular ` ``` ` — the escaped versions above are an artifact of writing this plan as Markdown-inside-Markdown. Use the unescaped form in the actual file.)

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Update README for Makefile-based install"
```

---

### Task 10: Integration check

**Files:** none (verification only).

- [ ] **Step 1: Snapshot shell-init state**

Run:
```bash
ls -l ~/.bash_profile ~/.bashrc ~/.zprofile ~/.zshrc 2>&1 || true
echo '---'
grep -H 'brew shellenv' ~/.zprofile ~/.zshrc 2>/dev/null || echo "(no brew shellenv lines in zsh files)"
echo '---'
grep -Fqs '[ -f ~/.bashrc ] && . ~/.bashrc' ~/.bash_profile && echo "bash_profile sources bashrc: yes" || echo "bash_profile sources bashrc: no"
```

Note the output. After the make run below, expect:
- `.bashrc` exists (created if missing)
- `bash_profile sources bashrc: yes`
- no `brew shellenv` lines in `.zprofile`/`.zshrc`

(Task 5's verification may have already left things in this state. If so, that's fine — Task 10 just confirms it.)

- [ ] **Step 2: Run `make claude-code` (verify path)**

Run: `make claude-code`
Expected: each guard passes silently (`xcode-clt`, `homebrew`, `claude-code` all installed), no script invocations needed. `bash-init` always runs but does no work because everything is already in order. Total runtime: under a second.

- [ ] **Step 3: Run `make claude-code` again to confirm cheap re-run**

Run: `make claude-code`
Expected: same as Step 2 — fast, no install, no output (or very minimal output).

- [ ] **Step 4: Optional — install Maccy for real**

This is the only step that performs a fresh install; gate it on user confirmation. Run only if you want Maccy installed now.

Run: `make maccy`
Expected:
- `xcode-clt`, `bash-init`, `homebrew` guards all pass
- `maccy` guard fails (no `/Applications/Maccy.app`)
- `install-maccy.sh` runs, eval's brew shellenv, runs `brew install --cask maccy`
- Maccy installs

After: `make maccy` again should pass the guard and exit instantly.

- [ ] **Step 5: Final state check**

Run: `git status; git log --oneline -12`
Expected: clean working tree; commits from tasks 1–9 present (10 commits in total since branch was cut, including the original spec/plan commits).

---

## Notes for the implementer

- **Tabs in Makefile recipes.** Make rejects spaces. If the file is created via a tool that auto-converts tabs, fix it. The `cat -A` check in Task 2 verifies this.
- **`sed -i ''` is intentional.** macOS's BSD sed requires an argument after `-i` (an empty string for "no backup"). GNU sed doesn't. Don't "fix" this.
- **Script invocation from `make`** is `bash install-foo.sh`, not `./install-foo.sh`, so the executable bit is irrelevant. Don't bother with `chmod +x`.
- **The `set -e` interactions you'd worry about in a more complex bash codebase don't really apply here** — each script is short and linear, with no `||` chains in conditional positions that would suppress `set -e`. If a script does anything tricky, the spec or plan calls it out.
- **bash 3.2 compatibility:** macOS ships bash 3.2; avoid bash 4+ features. Nothing in this plan uses any.
