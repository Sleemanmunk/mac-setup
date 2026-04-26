# CLAUDE.md

Project conventions for `mac-setup`. Read this before adding or modifying install scripts.

## Architecture in one paragraph

`Makefile` owns the dependency graph and the "skip if already installed" guards. Each `install-<name>.sh` is a thin script that *just does the install* — no dispatch, no shared library, no inter-script `require` calls. To install something, the user runs `make <target>`; make walks the deps and only invokes a script when its inline guard fails. Full rationale lives in [docs/superpowers/specs/2026-04-25-install-script-dependencies-design.md](docs/superpowers/specs/2026-04-25-install-script-dependencies-design.md).

## Adding a new install

To add a tool `foo`:

1. **Create `install-foo.sh`** — a thin script that does the install (see template below).
2. **Add a target to the `Makefile`** with the right dependencies and an inline guard.

That's it. No edits to other scripts. No registration step beyond the Makefile entry.

### Makefile target template

```makefile
foo: <space-separated deps>
	@<cheap-check> || bash install-foo.sh
```

Add `foo` to the `.PHONY:` line at the top.

- **Deps** are other targets — typically `homebrew` for any cask/formula install. The graph is encoded only here.
- **The guard** is the "is this already installed?" check. Pick the cheapest, most authoritative check (see "Choosing a guard" below). If the guard exits 0, the script is never invoked.
- **TAB-indent recipe lines.** Make is strict; spaces silently break things. Verify with `cat -A Makefile` and look for `^I` at the start of recipe lines.
- **`@` suppresses echo** so the user only sees output when something actually runs.
- **`$$` escapes `$`** in recipes (make's two-pass interpolation). The shell sees `$(...)` and `$VAR`.

### Cask install script template

For a Homebrew cask (the common case):

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"
brew install --cask foo
```

The two `eval` lines load brew onto PATH if it isn't already (only one path exists on any given machine). This matters because make's `homebrew` dep guarantees brew is *installed*, not that it's on PATH in the current shell.

### Worked example: adding Rectangle (window manager)

`Makefile` (added line + new target):

```makefile
.PHONY: claude-code maccy rectangle homebrew bash-init bash-shell xcode-clt
...
rectangle: homebrew
	@[ -d /Applications/Rectangle.app ] || bash install-rectangle.sh
```

`install-rectangle.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew    ]] && eval "$(/usr/local/bin/brew shellenv)"
brew install --cask rectangle
```

User then runs `make rectangle`. Done.

## Choosing a guard

The guard goes in the Makefile recipe before `||`. It must be cheap and side-effect-free.

| Tool type | Recommended guard |
|---|---|
| CLI on PATH | `command -v <bin> >/dev/null 2>&1` |
| GUI app installed via cask | `[ -d /Applications/<Name>.app ]` |
| File or directory exists | `[ -f <path> ]` / `[ -d <path> ]` |
| Login shell setting | `[ "$$(dscl . -read $$HOME UserShell \| awk '{print $$2}')" = "/bin/bash" ]` |

For complex multi-part state (multiple files, multiple lines), don't try to cram it into the guard — make the script itself idempotent (each mutation guarded internally) and skip the inline guard. `install-bash-init.sh` is the example: its Makefile recipe just runs the script unconditionally because the script's mutations are individually guarded.

## Script conventions

- **Top of every script:** `#!/usr/bin/env bash` then `set -euo pipefail`. No exceptions.
- **Idempotency:** scripts must be safe to invoke directly via `bash install-foo.sh`, not just via `make`. For naturally-idempotent operations (`brew install`, `dscl . -change` to the current shell, etc.) just call them. For file mutations, guard each one — see `install-bash-init.sh` for the pattern (e.g. `grep -Fqs "$LINE" "$FILE" || echo "$LINE" >> "$FILE"`).
- **No `lib/` directory.** A previous design had one; we deliberately removed it. Each script is fully self-contained. If you find yourself wanting to share helpers across scripts, that's a signal to reconsider — usually the right answer is to keep each script's logic small enough to not need helpers, or push the orchestration into the Makefile.
- **No `verify`/`install` subcommand dispatch.** That was also a previous design we removed. Scripts have one job; the Makefile decides whether to run them.
- **Bash 3.2 compatible.** macOS ships bash 3.2 (the system bash). Don't use bash-4 features: no associative arrays, no `${var,,}`, no `mapfile`, no `&>>`. Quote variables, prefer `[[` over `[`, use `$(...)` over backticks.

## macOS gotchas to remember

- **BSD sed needs `sed -i ''`** (note the empty-string argument). GNU sed uses `sed -i`. Don't "fix" the empty string.
- **`dscl . -read $HOME UserShell`** is the authoritative read of a user's login shell. `$SHELL` lags after a `chsh` / `dscl . -change` until the next login.
- **`make` itself is provided by the Xcode Command Line Tools.** On a fresh Mac without CLT, `/usr/bin/make` is a stub that triggers the CLT GUI installer when invoked. The chicken-and-egg of "we need make to install CLT" self-resolves: the user clicks through the GUI, re-runs `make <whatever>`, and the chain proceeds. The `xcode-clt` target still exists for tools that depend directly on CLT without going through brew.
- **Login shell vs interactive shell init files.** Bash login shells read `~/.bash_profile`; interactive non-login shells read `~/.bashrc`. We use a single source of truth: write all init lines to `~/.bashrc`, and `install-bash-init.sh` ensures `~/.bash_profile` sources `~/.bashrc`. So when a tool needs to add to shell init, append to `~/.bashrc`.
- **`brew install` is idempotent** — running it on an already-installed package is a fast no-op. Don't add a redundant "is it installed" check inside the script; the Makefile guard already handles that.

## When NOT to follow the pattern

The patterns above are right for "install a tool." If you find yourself wanting:

- A target that *configures* something rather than installs it (dotfiles, defaults write, etc.) — the same Make-orchestrates-thin-scripts shape applies, but the guard might check a setting value rather than a binary's existence.
- A script that does multiple distinct things — split it. Each script should be a one-line description ("install Maccy", "set login shell to bash"). If you need "and" in the description, you probably need two scripts.

If something doesn't fit the pattern, prefer extending the conventions over adding back machinery (no shared libs, no dispatchers, no helper scripts that wrap other scripts).
