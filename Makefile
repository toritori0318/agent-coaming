COAMING_TEAM_ID ?=
DERIVED = build
PROJECT = AgentCoaming.xcodeproj
SCHEME = CoamingHost
APP = Agent Coaming.app

.PHONY: generate build test check run install

generate:
	@if [ -z "$(COAMING_TEAM_ID)" ]; then \
		echo "COAMING_TEAM_ID is not set."; \
		echo "Add an Apple ID in Xcode → Settings → Accounts and copy the Personal Team ID."; \
		echo "Example: COAMING_TEAM_ID=XXXXXXXXXX make generate"; \
		exit 1; \
	fi
	@printf 'COAMING_TEAM_ID = %s\nDEVELOPMENT_TEAM = $$(COAMING_TEAM_ID)\n' "$(COAMING_TEAM_ID)" > Config.xcconfig
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' -derivedDataPath $(DERIVED) build

test:
	swift test --package-path CoamingCore

check: test
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
