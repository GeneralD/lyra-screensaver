PROJECT := LyraScreenSaver.xcodeproj
TARGET  := LyraScreenSaver
CONFIG  := Release
DERIVED := build
SAVER   := $(DERIVED)/Build/Products/$(CONFIG)/$(TARGET).saver
INSTALL_DIR := $(HOME)/Library/Screen Savers

.PHONY: generate build install uninstall clean

generate: ## Generate the Xcode project from project.yml
	xcodegen generate

build: generate ## Build the .saver bundle
	# -derivedDataPath (not SYMROOT): relocating output via SYMROOT desyncs the
	# inter-package module search paths for SwiftPM deps, so a transitive dep
	# (e.g. combine-schedulers) fails to find its own dep (ConcurrencyExtras).
	# -derivedDataPath relocates the whole build tree coherently instead.
	# -skipMacroValidation trusts lyra's papyrus macro plugin non-interactively.
	xcodebuild -project $(PROJECT) -scheme $(TARGET) -configuration $(CONFIG) \
		-skipMacroValidation -derivedDataPath $(DERIVED) build \
		MACOSX_DEPLOYMENT_TARGET=14.0

install: build ## Build then install into ~/Library/Screen Savers
	rm -rf "$(INSTALL_DIR)/$(TARGET).saver"
	mkdir -p "$(INSTALL_DIR)"
	cp -R "$(SAVER)" "$(INSTALL_DIR)/"
	@echo "Installed. Open System Settings > Screen Saver and pick $(TARGET)."

uninstall: ## Remove the installed .saver
	rm -rf "$(INSTALL_DIR)/$(TARGET).saver"

clean: ## Remove build artifacts and the generated project
	rm -rf $(DERIVED) $(PROJECT)
