# iOS IPA build pipeline. Requires Team and signing set up in Xcode
# (i.e. DEVELOPMENT_TEAM on the target, and Xcode → Settings → Accounts).

IOS_BUILD_DIR    := out/build/ios
IOS_XCODEPROJ    := $(IOS_BUILD_DIR)/fallout2-ce.xcodeproj
IOS_ARCHIVE      := $(IOS_BUILD_DIR)/fallout2-ce.xcarchive
IOS_EXPORT_DIR   := $(IOS_BUILD_DIR)/export
IOS_EXPORT_PLIST := ExportOptions.plist

.PHONY: ipa ios-configure ios-archive ios-export ios-clean

ipa: ios-export
	@echo ""
	@echo "IPA ready: $(IOS_EXPORT_DIR)/fallout2-ce.ipa"

ios-configure:
	cmake --preset ios

ios-archive: ios-configure
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
