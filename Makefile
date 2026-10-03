COAMING_TEAM_ID ?=
DERIVED = build
PROJECT = AgentCoaming.xcodeproj
SCHEME = CoamingHost
APP = Agent Coaming.app

.PHONY: generate build test check run install dmg

# COAMING_CURSOR=1 includes the optional Cursor path. The default build leaves it out. See ProviderID.included.
generate:
	@if [ -z "$(COAMING_TEAM_ID)" ]; then \
		echo "COAMING_TEAM_ID is not set."; \
		echo "Add an Apple ID in Xcode → Settings → Accounts and copy the Personal Team ID."; \
		echo "Example: COAMING_TEAM_ID=XXXXXXXXXX make generate"; \
		exit 1; \
	fi
	@if [ "$(COAMING_CURSOR)" = "1" ]; then cursor_condition=COAMING_CURSOR; else cursor_condition=; fi; \
	printf 'COAMING_TEAM_ID = %s\nDEVELOPMENT_TEAM = $$(COAMING_TEAM_ID)\nCOAMING_CURSOR_CONDITION = %s\n' "$(COAMING_TEAM_ID)" "$$cursor_condition" > Config.xcconfig
	xcodegen generate

build: generate
	@mkdir -p $(DERIVED)
	@if [ "$$(cat $(DERIVED)/cursor-flag 2>/dev/null)" != "$(COAMING_CURSOR)" ]; then \
		rm -rf $(DERIVED)/Build $(DERIVED)/SourcePackages $(DERIVED)/ModuleCache.noindex; \
		printf '%s' "$(COAMING_CURSOR)" > $(DERIVED)/cursor-flag; \
	fi
	COAMING_CURSOR="$(COAMING_CURSOR)" xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' -derivedDataPath $(DERIVED) build

# Tests compile the optional Cursor path so it stays covered. The app build does not, unless COAMING_CURSOR=1.
test:
	COAMING_CURSOR=1 swift test --package-path CoamingCore

check:
	env -u COAMING_CURSOR swift build --package-path CoamingCore --scratch-path $(DERIVED)/spm-off
	$(MAKE) test
	python3 scripts/check.py

run: build
	open "$(DERIVED)/Build/Products/Debug/$(APP)"

install: build
	mkdir -p "$(HOME)/Applications" "$(HOME)/Library/Application Support/Agent Coaming"
	rm -rf "$(HOME)/Applications/$(APP).new"
	cp -R "$(DERIVED)/Build/Products/Debug/$(APP)" "$(HOME)/Applications/$(APP).new"
	rm -rf "$(HOME)/Applications/$(APP)"
	mv "$(HOME)/Applications/$(APP).new" "$(HOME)/Applications/$(APP)"
	install -m 755 scripts/claude-statusline.sh "$(HOME)/Library/Application Support/Agent Coaming/claude-statusline.sh"
	@echo 'To show Claude reset times, add this to ~/.claude/settings.json:'
	@echo '  "statusLine": {"type": "command", "command": "~/Library/Application\\\\ Support/Agent\\\\ Coaming/claude-statusline.sh"}'
	@echo 'If you already have a status line: "command": "~/Library/Application\\\\ Support/Agent\\\\ Coaming/claude-statusline.sh <existing command>"'

# Public disk image. Refuses COAMING_CURSOR. The notarization password stays in the login keychain.
dmg:
	@if [ -z "$(COAMING_TEAM_ID)" ]; then \
		echo "COAMING_TEAM_ID is not set."; \
		echo "Use the paid Apple Developer Program team. A Personal Team cannot notarize."; \
		echo "Example: COAMING_TEAM_ID=XXXXXXXXXX make dmg"; \
		exit 1; \
	fi
	@if [ -n "$(COAMING_CURSOR)" ]; then \
		echo "make dmg builds the public disk image and leaves Cursor out. Unset COAMING_CURSOR."; \
		exit 1; \
	fi
	env -u COAMING_CURSOR COAMING_TEAM_ID="$(COAMING_TEAM_ID)" ./scripts/release-dmg.sh
