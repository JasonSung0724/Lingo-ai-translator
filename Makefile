# Same location the installer/Sparkle use — two coexisting copies would fight.
APP_DIR ?= /Applications

.PHONY: build run install clean

build:
	@bash scripts/build.sh release

install: build
	@mkdir -p "$(APP_DIR)"
	@rm -rf "$(APP_DIR)/Lingo.app"
	@cp -R Lingo.app "$(APP_DIR)/Lingo.app"
	@rm -rf Lingo.app
	@echo "✓ Installed to $(APP_DIR)/Lingo.app"

run: install
	@open "$(APP_DIR)/Lingo.app"

clean:
	@rm -rf .build Lingo.app
	@echo "✓ Cleaned"
