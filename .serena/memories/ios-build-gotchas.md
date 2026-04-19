# iOS CMake + Xcode build gotchas

## `VERBATIM` on `add_custom_command` breaks Xcode build-setting expansion

If POST_BUILD commands use `$<TARGET_BUNDLE_DIR:target>`, CMake's Xcode generator expands it to `$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/target.app`. With `VERBATIM` set, CMake escapes the `$`, so Xcode sees literal `${EFFECTIVE_PLATFORM_NAME}` and creates a phantom `Debug${EFFECTIVE_PLATFORM_NAME}/` directory. Drop `VERBATIM` for any POST_BUILD that uses `TARGET_BUNDLE_DIR`.

## `SKIP_INSTALL=NO` + `INSTALL_PATH=$(LOCAL_APPS_DIR)` required for archives

CMake's Xcode generator defaults `SKIP_INSTALL=YES` on application targets. That makes `xcodebuild archive` produce an empty `.xcarchive` with no `Products/Applications/fallout2-ce.app`, which means no `ApplicationProperties` in the archive's `Info.plist`, which means `exportArchive` fails with a cryptic `Unknown Distribution Error` and `expected one {} but found release-testing`. Fix in the target properties:

```cmake
XCODE_ATTRIBUTE_INSTALL_PATH "$(LOCAL_APPS_DIR)"
XCODE_ATTRIBUTE_SKIP_INSTALL "NO"
```

## `CMakePresets.json` kills target-level signing

`darwin-base` preset sets `CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""` globally. Override at the target level with `XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "Apple Development"` + `XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"` + `XCODE_ATTRIBUTE_DEVELOPMENT_TEAM`. Otherwise archives come out unsigned.

## Bundle ID has two separate sources that must agree

- `XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER` — used by Xcode for code signing and installation-launch matching.
- `os/ios/Info.plist`'s `CFBundleIdentifier = ${MACOSX_BUNDLE_GUI_IDENTIFIER}` — CMake-substituted at configure time from the `MACOSX_BUNDLE_GUI_IDENTIFIER` variable, baked into the built binary.

Mismatch produces "A binary with bundle identifier X is installed but is different from Y that Xcode is asked to launch". Both must resolve to the same value (we plumb both from `IOS_BUNDLE_IDENTIFIER`).

## Xcode 26 renamed ExportOptions.plist `method` values

- `development` → `debugging`
- `ad-hoc` → `release-testing`
- `app-store` → `app-store-connect`
- `enterprise` (unchanged)

## Per-developer signing stored outside the repo

`ios-signing.cmake` (gitignored) sets `IOS_BUNDLE_IDENTIFIER` + `IOS_DEVELOPMENT_TEAM` as regular variables; CMakeLists.txt uses `if(NOT DEFINED ...)` so the override wins. Using `CACHE STRING` with a default here is wrong — the default wins silently.

## Regen dance after CMake-side changes

Xcode's "up to date" detection often skips POST_BUILD commands even after CMakeLists.txt edits. To force:

```
rm -rf out/build/ios
cmake --preset ios
# then Cmd+Shift+K and Cmd+R in Xcode (xcodeproj must be reopened)
```

## Top-level Makefile produces signed IPA

`make ipa` runs: `cmake --preset ios` → `xcodebuild ... archive` → `xcodebuild -exportArchive`. Needs `ExportOptions.plist` (in repo) and `ios-signing.cmake` (local, gitignored). Output at `out/build/ios/export/fallout2-ce.ipa`.
