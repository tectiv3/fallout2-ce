# iOS IPA build pipeline. Requires Team and signing set up in Xcode
# (i.e. DEVELOPMENT_TEAM on the target, and Xcode → Settings → Accounts).

IOS_BUILD_DIR    := out/build/ios
IOS_XCODEPROJ    := $(IOS_BUILD_DIR)/fallout2-ce.xcodeproj
IOS_ARCHIVE      := $(IOS_BUILD_DIR)/fallout2-ce.xcarchive
IOS_EXPORT_DIR   := $(IOS_BUILD_DIR)/export
IOS_EXPORT_PLIST := ExportOptions.plist

.PHONY: ipa ipa-full ios-configure ios-configure-full ios-archive ios-export ios-clean ios-serve ios-serve-lan ipa-full-serve ipa-serve ipa-serve-lan

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
	rm -rf $(IOS_EXPORT_DIR).tmp
	xcodebuild -exportArchive \
		-archivePath $(IOS_ARCHIVE) \
		-exportPath $(IOS_EXPORT_DIR).tmp \
		-exportOptionsPlist $(IOS_EXPORT_PLIST)
	rm -rf $(IOS_EXPORT_DIR)
	mv $(IOS_EXPORT_DIR).tmp $(IOS_EXPORT_DIR)

ios-clean:
	rm -rf $(IOS_ARCHIVE) $(IOS_EXPORT_DIR)

# Serve the already-built IPA over OTA via a Tailscale funnel (public HTTPS).
ios-serve:
	@scripts/serve-ipa.sh

# Serve the already-built IPA over OTA on the local LAN only (mkcert HTTPS).
# One-time setup: trust the mkcert root CA on the iPad (script prints how).
ios-serve-lan:
	@scripts/serve-ipa-lan.sh

# Build the full IPA (includes game data) and immediately serve it for OTA.
ipa-full-serve: ipa-full ios-serve

# Build the slim IPA and immediately serve it for OTA.
ipa-serve: ipa ios-serve

# Build the slim IPA and serve it over the LAN only.
ipa-serve-lan: ipa ios-serve-lan
