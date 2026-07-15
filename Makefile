PROJECT := LyraScreenSaver.xcodeproj
TARGET  := LyraScreenSaver
CONFIG  := Release
SAVER   := build/$(CONFIG)/$(TARGET).saver
INSTALL_DIR := $(HOME)/Library/Screen Savers

.PHONY: generate build install uninstall clean

generate: ## Generate the Xcode project from project.yml
	xcodegen generate

build: generate ## Build the .saver bundle
	# EXPLICIT_BUILT_MODULES/SWIFT_ENABLE_EXPLICIT_MODULES=NO: works around
	# a known, still-open Xcode 26 beta "Explicitly Built Modules" bug
	# (Swift Forums: "Xcode 26: Unable to find module dependency"). MUST be
	# passed as a global xcodebuild argument, not a project.yml per-target
	# setting — a per-target setting does not propagate to the separate
	# SwiftPM package sub-project targets (combine-schedulers, swift-clocks)
	# that also need it; verified empirically. Harmless no-op on older/
	# stable Xcode toolchains.
	xcodebuild -project $(PROJECT) -scheme $(TARGET) -configuration $(CONFIG) \
		-skipMacroValidation build SYMROOT=build \
		MACOSX_DEPLOYMENT_TARGET=14.0 \
		EXPLICIT_BUILT_MODULES=NO \
		SWIFT_ENABLE_EXPLICIT_MODULES=NO

install: build ## Build then install into ~/Library/Screen Savers
	rm -rf "$(INSTALL_DIR)/$(TARGET).saver"
	mkdir -p "$(INSTALL_DIR)"
	cp -R "$(SAVER)" "$(INSTALL_DIR)/"
	@echo "Installed. Open System Settings > Screen Saver and pick $(TARGET)."

uninstall: ## Remove the installed .saver
	rm -rf "$(INSTALL_DIR)/$(TARGET).saver"

clean: ## Remove build artifacts and the generated project
	rm -rf build $(PROJECT)
