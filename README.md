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
