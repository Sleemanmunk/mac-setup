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
