# iOS IPA build pipeline. Requires Team and signing set up in Xcode
# (i.e. DEVELOPMENT_TEAM on the target, and Xcode → Settings → Accounts).

IOS_BUILD_DIR    := out/build/ios
IOS_XCODEPROJ    := $(IOS_BUILD_DIR)/fallout2-ce.xcodeproj
IOS_ARCHIVE      := $(IOS_BUILD_DIR)/fallout2-ce.xcarchive
IOS_EXPORT_DIR   := $(IOS_BUILD_DIR)/export
IOS_EXPORT_PLIST := ExportOptions.plist

.PHONY: ipa ipa-full ipa-lean-serve ios-version-bump ios-configure ios-configure-full ios-configure-lean ios-archive ios-export ios-clean ios-serve ipa-full-serve ipa-serve

# Slim IPA: bundles mods + configs only. User supplies master.dat /
# critter.dat / data/sound in the iPad's Documents via Files app.
ipa: ios-version-bump ios-configure ios-export
	@echo ""
	@echo "Slim IPA ready: $(IOS_EXPORT_DIR)/fallout2-ce.ipa"

# All-inclusive IPA: bundles game data too. Requires master.dat,
# critter.dat, and data/sound/ present in the repo root. Useful when
# sending a ready-to-run build to someone else.
ipa-full: ios-version-bump ios-configure-full ios-export
	@echo ""
	@echo "All-inclusive IPA ready: $(IOS_EXPORT_DIR)/fallout2-ce.ipa"

# Bumps the patch component of os/ios/version.txt (gitignored). CMakeLists.txt
# picks the new value up at configure time for CFBundleShortVersionString and
# CFBundleVersion.
ios-version-bump:
	@scripts/ios-bump-version.sh

ios-configure:
	cmake --preset ios -DIOS_BUNDLE_ASSETS=OFF

ios-configure-full:
	cmake --preset ios -DIOS_BUNDLE_ASSETS=ON

ios-configure-lean:
	cmake --preset ios -DIOS_BUNDLE_MODS=OFF -DIOS_BUNDLE_ASSETS=OFF

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

# Serve the already-built IPA over OTA: one HTTPS listener on the LAN with a
# mkcert cert, plus a Tailscale Funnel-backed public URL, both fed from the
# same files. Index page exposes the mkcert root CA as a plain download link.
ios-serve:
	@scripts/serve-ipa.sh

# Build the full IPA (includes game data) and immediately serve it for OTA.
ipa-full-serve: ipa-full ios-serve

# Build the slim IPA and immediately serve it for OTA.
ipa-serve: ipa ios-serve

# Lean IPA: bundles only default configs (fallout2.cfg, ddraw.ini, f2_res.ini,
# f2_res.dat). No mods, no game data. Assumes the user's Documents already has
# a working install (master.dat, critter.dat, data/, mods/). Builds, signs,
# and serves in one shot.
ipa-lean-serve: ios-version-bump ios-configure-lean ios-export ios-serve
