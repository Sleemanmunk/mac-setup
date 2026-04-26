.PHONY: claude-code maccy node homebrew bash-init bash-shell xcode-clt

xcode-clt:
	@xcode-select -p >/dev/null 2>&1 || bash install-xcode-clt.sh

bash-shell:
	@[ "$$(dscl . -read $$HOME UserShell | awk '{print $$2}')" = "/bin/bash" ] \
		|| bash install-bash-shell.sh

bash-init: bash-shell
	@bash install-bash-init.sh

homebrew: xcode-clt bash-init
	@bash install-homebrew.sh

claude-code: homebrew
	@command -v claude >/dev/null 2>&1 || bash install-claude-code.sh

maccy: homebrew
	@[ -d /Applications/Maccy.app ] || bash install-maccy.sh

node: homebrew
	@command -v node >/dev/null 2>&1 || bash install-node.sh
