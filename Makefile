# Janitor - macOS 开发环境智能清理工具
# Makefile for building, packaging, and releasing

.PHONY: help build build-release clean test archive notarize dmg release-github install uninstall

# Project Configuration
PROJECT_NAME = Janitor
SCHEME = Janitor
WORKSPACE = Janitor.xcodeproj
BUILD_DIR = build
ARCHIVE_PATH = $(BUILD_DIR)/$(PROJECT_NAME).xcarchive
APP_NAME = $(PROJECT_NAME).app
DMG_NAME = $(PROJECT_NAME)
BUNDLE_ID = com.janitor.macos

# Build Configuration
CONFIGURATION_DEBUG = Debug
CONFIGURATION_RELEASE = Release
DESTINATION = "generic/platform=macOS"

# Version (read from Info.plist)
VERSION = $(shell /usr/libexec/PlistBuddy -c "print CFBundleShortVersionString" "$(BUILD_DIR)/Release/$(APP_NAME)/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
BUILD_NUMBER = $(shell /usr/libexec/PlistBuddy -c "print CFBundleVersion" "$(BUILD_DIR)/Release/$(APP_NAME)/Contents/Info.plist" 2>/dev/null || echo "1")

# GitHub Release Configuration  
GITHUB_REPO = $(shell git config remote.origin.url | sed 's/.*github.com[:/]\(.*\)\.git/\1/')
RELEASE_NOTES = "Release $(VERSION) - See CHANGELOG.md for details"

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Janitor Build System$(NC)"
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)
	rm -rf DerivedData
	xcodebuild clean -project $(WORKSPACE) -scheme $(SCHEME) -configuration $(CONFIGURATION_RELEASE)
	@echo "$(GREEN)Clean completed$(NC)"

build: ## Build debug version
	@echo "$(YELLOW)Building debug version...$(NC)"
	xcodebuild build \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION_DEBUG) \
		-destination $(DESTINATION) \
		-derivedDataPath $(BUILD_DIR)/DerivedData
	@echo "$(GREEN)Debug build completed$(NC)"

build-release: ## Build release version
	@echo "$(YELLOW)Building release version...$(NC)"
	mkdir -p $(BUILD_DIR)
	xcodebuild build \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION_RELEASE) \
		-destination $(DESTINATION) \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		SYMROOT=$(BUILD_DIR) \
		DSTROOT=$(BUILD_DIR)/dst
	@echo "$(GREEN)Release build completed$(NC)"

test: ## Run unit tests
	@echo "$(YELLOW)Running tests...$(NC)"
	xcodebuild test \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination "platform=macOS" \
		-derivedDataPath $(BUILD_DIR)/DerivedData
	@echo "$(GREEN)Tests completed$(NC)"

archive: build-release ## Create application archive
	@echo "$(YELLOW)Creating archive...$(NC)"
	xcodebuild archive \
		-project $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION_RELEASE) \
		-destination $(DESTINATION) \
		-archivePath $(ARCHIVE_PATH) \
		-derivedDataPath $(BUILD_DIR)/DerivedData
	@echo "$(GREEN)Archive created at $(ARCHIVE_PATH)$(NC)"

export-app: archive ## Export application from archive
	@echo "$(YELLOW)Exporting application...$(NC)"
	mkdir -p $(BUILD_DIR)/export
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(BUILD_DIR)/export \
		-exportOptionsPlist exportOptions.plist || \
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(BUILD_DIR)/export \
		-exportFormat app
	@echo "$(GREEN)Application exported to $(BUILD_DIR)/export$(NC)"

create-export-plist: ## Create export options plist if it doesn't exist
	@if [ ! -f exportOptions.plist ]; then \
		echo "$(YELLOW)Creating exportOptions.plist...$(NC)"; \
		echo '<?xml version="1.0" encoding="UTF-8"?>' > exportOptions.plist; \
		echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> exportOptions.plist; \
		echo '<plist version="1.0">' >> exportOptions.plist; \
		echo '<dict>' >> exportOptions.plist; \
		echo '    <key>method</key>' >> exportOptions.plist; \
		echo '    <string>developer-id</string>' >> exportOptions.plist; \
		echo '    <key>teamID</key>' >> exportOptions.plist; \
		echo '    <string>YOUR_TEAM_ID</string>' >> exportOptions.plist; \
		echo '</dict>' >> exportOptions.plist; \
		echo '</plist>' >> exportOptions.plist; \
		echo "$(RED)Please update YOUR_TEAM_ID in exportOptions.plist$(NC)"; \
	fi

dmg: export-app ## Create DMG installer
	@echo "$(YELLOW)Creating DMG installer...$(NC)"
	rm -f $(BUILD_DIR)/$(DMG_NAME).dmg
	rm -rf $(BUILD_DIR)/dmg-temp
	mkdir -p $(BUILD_DIR)/dmg-temp
	cp -R $(BUILD_DIR)/export/$(APP_NAME) $(BUILD_DIR)/dmg-temp/
	ln -sf /Applications $(BUILD_DIR)/dmg-temp/Applications
	hdiutil create -volname "$(PROJECT_NAME)" \
		-srcfolder $(BUILD_DIR)/dmg-temp \
		-ov -format UDZO \
		$(BUILD_DIR)/$(DMG_NAME)-$(VERSION).dmg
	rm -rf $(BUILD_DIR)/dmg-temp
	@echo "$(GREEN)DMG created: $(BUILD_DIR)/$(DMG_NAME)-$(VERSION).dmg$(NC)"

notarize: dmg ## Notarize the DMG (requires Apple ID credentials)
	@echo "$(YELLOW)Notarizing DMG...$(NC)"
	@echo "$(RED)Note: Notarization requires Apple Developer account and app-specific password$(NC)"
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(APPLE_ID_PASSWORD)" ]; then \
		echo "$(RED)Please set APPLE_ID and APPLE_ID_PASSWORD environment variables$(NC)"; \
		echo "Example: make notarize APPLE_ID=your@email.com APPLE_ID_PASSWORD=@keychain:AC_PASSWORD"; \
		exit 1; \
	fi
	xcrun notarytool submit $(BUILD_DIR)/$(DMG_NAME)-$(VERSION).dmg \
		--apple-id $(APPLE_ID) \
		--password $(APPLE_ID_PASSWORD) \
		--team-id $(TEAM_ID) \
		--wait
	xcrun stapler staple $(BUILD_DIR)/$(DMG_NAME)-$(VERSION).dmg
	@echo "$(GREEN)DMG notarized and stapled$(NC)"

install: export-app ## Install the application locally
	@echo "$(YELLOW)Installing $(APP_NAME) to /Applications...$(NC)"
	sudo rm -rf /Applications/$(APP_NAME)
	sudo cp -R $(BUILD_DIR)/export/$(APP_NAME) /Applications/
	@echo "$(GREEN)$(APP_NAME) installed successfully$(NC)"

uninstall: ## Uninstall the application
	@echo "$(YELLOW)Uninstalling $(APP_NAME)...$(NC)"
	sudo rm -rf /Applications/$(APP_NAME)
	@echo "$(GREEN)$(APP_NAME) uninstalled$(NC)"

version: ## Show current version
	@echo "Current version: $(VERSION) (build $(BUILD_NUMBER))"

release-github: dmg ## Create GitHub release
	@echo "$(YELLOW)Creating GitHub release...$(NC)"
	@if [ -z "$(GITHUB_TOKEN)" ]; then \
		echo "$(RED)Please set GITHUB_TOKEN environment variable$(NC)"; \
		echo "Get token from: https://github.com/settings/tokens"; \
		exit 1; \
	fi
	@if ! command -v gh > /dev/null; then \
		echo "$(RED)GitHub CLI (gh) is required. Install with: brew install gh$(NC)"; \
		exit 1; \
	fi
	gh release create v$(VERSION) \
		$(BUILD_DIR)/$(DMG_NAME)-$(VERSION).dmg \
		--title "$(PROJECT_NAME) v$(VERSION)" \
		--notes $(RELEASE_NOTES) \
		--draft
	@echo "$(GREEN)GitHub release created: https://github.com/$(GITHUB_REPO)/releases/tag/v$(VERSION)$(NC)"

release-prep: clean test archive dmg ## Prepare for release (clean, test, build, package)
	@echo "$(GREEN)Release preparation completed!$(NC)"
	@echo "Next steps:"
	@echo "1. Test the DMG: $(BUILD_DIR)/$(DMG_NAME)-$(VERSION).dmg"
	@echo "2. Notarize: make notarize APPLE_ID=your@email.com APPLE_ID_PASSWORD=@keychain:AC_PASSWORD"
	@echo "3. Create release: make release-github"

deps-check: ## Check for required dependencies
	@echo "$(YELLOW)Checking dependencies...$(NC)"
	@command -v xcodebuild >/dev/null 2>&1 || { echo "$(RED)xcodebuild not found. Please install Xcode.$(NC)"; exit 1; }
	@command -v hdiutil >/dev/null 2>&1 || { echo "$(RED)hdiutil not found.$(NC)"; exit 1; }
	@echo "$(GREEN)All dependencies satisfied$(NC)"

info: ## Show project information
	@echo "$(BLUE)Project Information:$(NC)"
	@echo "  Name: $(PROJECT_NAME)"
	@echo "  Version: $(VERSION)"
	@echo "  Build: $(BUILD_NUMBER)"
	@echo "  Bundle ID: $(BUNDLE_ID)"
	@echo "  GitHub Repo: $(GITHUB_REPO)"
	@echo "  Build Dir: $(BUILD_DIR)"