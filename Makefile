# iOS IPA + macOS build pipeline.
# Requires Team and signing set up in Xcode
# (i.e. DEVELOPMENT_TEAM on the target, and Xcode → Settings → Accounts).

IOS_BUILD_DIR    := out/build/ios
IOS_XCODEPROJ    := $(IOS_BUILD_DIR)/fallout2-ce.xcodeproj
IOS_ARCHIVE      := $(IOS_BUILD_DIR)/fallout2-ce.xcarchive
IOS_EXPORT_DIR   := $(IOS_BUILD_DIR)/export
IOS_EXPORT_PLIST := ExportOptions.plist

MAC_BUILD_DIR    := out/build/macos
MAC_XCODEPROJ    := $(MAC_BUILD_DIR)/fallout2-ce.xcodeproj
MAC_APP_NAME     := Fallout II Community Edition.app
MAC_APP          := $(MAC_BUILD_DIR)/Release/$(MAC_APP_NAME)
MAC_DIST_DIR     := $(MAC_BUILD_DIR)/dist
MAC_ZIP          := $(MAC_DIST_DIR)/fallout2-ce-macos.zip

.PHONY: ipa mac serve clean

# --- iOS ----------------------------------------------------------------------

# IPA: bundles default configs only. User supplies master.dat, critter.dat,
# data/, and mods/ in the iPad's Documents via Files app.
ipa:
	@scripts/ios-bump-version.sh
	cmake --preset ios -DIOS_BUNDLE_MODS=OFF -DIOS_BUNDLE_ASSETS=OFF
	rm -rf $(IOS_EXPORT_DIR).tmp
	xcodebuild \
		-project $(IOS_XCODEPROJ) \
		-scheme fallout2-ce \
		-configuration RelWithDebInfo \
		-destination 'generic/platform=iOS' \
		-archivePath $(IOS_ARCHIVE) \
		-skipPackagePluginValidation \
		archive
	xcodebuild -exportArchive \
		-archivePath $(IOS_ARCHIVE) \
		-exportPath $(IOS_EXPORT_DIR).tmp \
		-exportOptionsPlist $(IOS_EXPORT_PLIST)
	rm -rf $(IOS_EXPORT_DIR)
	mv $(IOS_EXPORT_DIR).tmp $(IOS_EXPORT_DIR)
	@echo ""
	@echo "IPA ready: $(IOS_EXPORT_DIR)/fallout2-ce.ipa"

# Serve the already-built IPA over OTA. See scripts/serve-ipa.sh for details.
serve:
	@scripts/serve-ipa.sh

# --- macOS --------------------------------------------------------------------

# macOS Release build. Codesigning happens automatically via CMake POST_BUILD
# when MAC_SIGNING_IDENTITY is set in ios-signing.cmake (Developer ID Application
# is the natural choice for local personal builds — gives stable TCC grants
# across rebuilds). Without that variable, the .app builds unsigned.
mac:
	cmake --preset macos
	xcodebuild \
		-project $(MAC_XCODEPROJ) \
		-scheme fallout2-ce \
		-configuration Release \
		-destination 'platform=macOS' \
		-skipPackagePluginValidation \
		build
	mkdir -p $(MAC_DIST_DIR)
	rm -f $(MAC_ZIP)
	cd $(MAC_BUILD_DIR)/Release && ditto -c -k --sequesterRsrc --keepParent "$(MAC_APP_NAME)" "$(CURDIR)/$(MAC_ZIP)"
	@echo ""
	@echo "Mac app ready: $(MAC_APP)"
	@echo "Distributable zip: $(MAC_ZIP)"

# --- Cleanup ------------------------------------------------------------------

clean:
	rm -rf out/build
