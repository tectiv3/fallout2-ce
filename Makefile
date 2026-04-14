# iOS IPA build pipeline. Requires Team and signing set up in Xcode
# (i.e. DEVELOPMENT_TEAM on the target, and Xcode → Settings → Accounts).

IOS_BUILD_DIR    := out/build/ios
IOS_XCODEPROJ    := $(IOS_BUILD_DIR)/fallout2-ce.xcodeproj
IOS_ARCHIVE      := $(IOS_BUILD_DIR)/fallout2-ce.xcarchive
IOS_EXPORT_DIR   := $(IOS_BUILD_DIR)/export
IOS_EXPORT_PLIST := ExportOptions.plist

.PHONY: ipa ipa-full ios-configure ios-configure-full ios-archive ios-export ios-clean

# Slim IPA: bundles mods + configs only. User supplies master.dat /
# critter.dat / data/sound in the iPad's Documents via Files app.
ipa: ios-configure ios-export
	@echo ""
	@echo "Slim IPA ready: $(IOS_EXPORT_DIR)/fallout2-ce.ipa"

# All-inclusive IPA: bundles game data too. Requires master.dat,
# critter.dat, and data/sound/ present in the repo root. Useful when
# sending a ready-to-run build to someone else.
ipa-full: ios-configure-full ios-export
	@echo ""
	@echo "All-inclusive IPA ready: $(IOS_EXPORT_DIR)/fallout2-ce.ipa"

ios-configure:
	cmake --preset ios -DIOS_BUNDLE_ASSETS=OFF

ios-configure-full:
	cmake --preset ios -DIOS_BUNDLE_ASSETS=ON

ios-archive:
	xcodebuild \
		-project $(IOS_XCODEPROJ) \
		-scheme fallout2-ce \
		-configuration RelWithDebInfo \
		-destination 'generic/platform=iOS' \
		-archivePath $(IOS_ARCHIVE) \
		-skipPackagePluginValidation \
		archive

ios-export: ios-archive
	rm -rf $(IOS_EXPORT_DIR)
	xcodebuild -exportArchive \
		-archivePath $(IOS_ARCHIVE) \
		-exportPath $(IOS_EXPORT_DIR) \
		-exportOptionsPlist $(IOS_EXPORT_PLIST)

ios-clean:
	rm -rf $(IOS_ARCHIVE) $(IOS_EXPORT_DIR)
