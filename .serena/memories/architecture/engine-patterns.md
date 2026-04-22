# Engine architectural patterns and conventions

## Input system architecture

### Dual keyboard state stores
- **Engine's `gPressedPhysicalKeys[]`** (`src/kb.cc`) – updated by `_kb_simulate_key()` and `_GNW95_process_key()` when SDL_KEYDOWN/UP events are polled in `src/input.cc`
- **SDL's own keyboard state** queried via `SDL_GetKeyboardState()` – updated only when SDL itself processes `SDL_KEYDOWN`/`SDL_KEYUP` events off its event queue
- `sfall_kb_is_key_pressed()` uses SDL's state, not the engine's. To simulate a held modifier that both engine and sfall see, use `SDL_PushEvent(SDL_KEYDOWN)` / `SDL_PushEvent(SDL_KEYUP)` – the SDL event loop propagates it to both paths.

### Mouse modes and touch handling
- `mouseDeviceUsesRelativeMode()` (`src/dinput.cc`): cached from `screenIsFullscreen()` at `mouseDeviceInitMode`. Controls whether `_mouse_simulate_input(dx, dy, btn)` adds deltas to cursor position (relative mode) or teleports to `(dx, dy)` (absolute mode).
- `gUseTouchscreenMode` (`src/touch.cc`): **defaults to true on iOS** (`#if __APPLE__ && TARGET_OS_IOS`), false on other platforms. When true, touch handler snaps cursor to finger position via `_mouse_set_position(centroid.x, centroid.y)`. On iOS, only gameplay and worldmap disable it; new screens get touchscreen mode automatically.
- UI screens use `touch_push_touchscreen_mode(true)` / `touch_pop_touchscreen_mode()` (stack-based) to preserve caller's state across nested transitions. Direct `touch_set_touchscreen_mode()` is reserved for top-level state (gameplay, worldmap, main menu).
- iOS touch gestures: 1-finger tap → left click, 2-finger tap → right click, 1-finger drag → cursor delta, 2-finger drag → mouse wheel, 3-finger swipe down → KEY_ESCAPE, 3-finger long-press → LSHIFT, 4-finger long-press → KEY_F6.

## UI state management patterns

### Disable/enable chains
- `gameUiDisable()` → calls `interfaceBarDisable()`, `keyboardDisable()`, `_gmouse_disable()`, sets `gGameUiDisabled = true`
- `gameUiEnable()` → reverses the chain
- Many screens (inventory, pipboy, dialog) call `gameUiDisable()`/`gameUiEnable()` around their modal loops
- UI action handlers should check both `interfaceBarEnabled()` and `gameUiIsDisabled()` before performing actions

### Interface bar states
- `interfaceBarEnabled()`: tracks whether interface buttons are enabled (`gInterfaceBarEnabled`)
- `interfaceBarHide()`/`interfaceBarShow()`: controls window visibility (`gInterfaceBarHidden`)
- The toolbar can be visible but disabled – need to check both states

### Inventory UI pattern
- `inventoryCommonInit()` saves `_inven_ui_was_disabled = gameUiIsDisabled()`, calls `gameUiEnable()` if UI was disabled
- `inventoryCommonFree()` restores previous UI state with `gameUiDisable(0)` if `_inven_ui_was_disabled` was true
- This pattern allows inventory to run while temporarily enabling UI if it was disabled

## Path handling conventions

### Windows backslash conversion
- Hardcoded paths throughout use Windows backslashes (`"mods\\*.dat"`, `"data\\MAPS\\AUTOMAP.DB"`)
- `compat_windows_path_to_native` (`src/platform_compat.cc:301`) converts `\\` to `/` on non-Windows systems
- Called by every compat file function: `compat_fopen`, `compat_gzopen`, `compat_mkdir`, `compat_rename`
- **Never use raw `fopen`** – always use `compat_fopen` to ensure cross-platform path compatibility

### Case sensitivity
- iOS filesystem is case-sensitive. Data files must match expected case (typically lowercase `master.dat`)
- `compat_resolve_path` walks paths and resolves case-insensitively on case-sensitive filesystems

### iOS path specifics
- CWD set to Documents (`iOSGetDocumentsPath()`) in `src/win32.cc` before SDL init
- All relative paths resolve from Documents
- Bundle path changes on app updates – symlinks are refreshed each launch

## Settings system migration

### Modern `Settings` struct vs legacy `gSfallConfig`
- New settings go in `Settings` struct (`src/settings.h`) with sub-structs: `SystemSettings`, `ScreenSettings`, etc.
- Registered via `SETTING`, `SETTING_P`, `SETTING_PATH` macros in `src/settings.cc`
- Automatically reads/writes to `fallout2.cfg` with sections matching sub-struct names
- Legacy `gSfallConfig` (`ddraw.ini`) is being migrated away from
- iOS UserDefaults overrides write to `settings.*` struct, not `configSetInt(&gSfallConfig, ...)`

### Path field handling
- `SETTING_PATH(f)` registers `settings.SECT.f##_path` with `normalizePath` post-processor
- `normalizePath` strips quotes, converts backslashes, resolves case

## iOS-specific architecture

### Bundle vs Documents split
- **Bundled in `.ipa`**: `fallout2.cfg`, `ddraw.ini`, `f2_res.ini`, `files/mods/` (both `.dat` and `.ini`)
- **User-supplied via Files app**: `master.dat`, `critter.dat`, `data/` tree (especially `data/sound/music/*.acm`)
- **Writable/state**: `Documents/data/SAVEGAME/`, `Documents/data/MAPS/`, `Documents/data/proto/`, `Documents/mods/*.ini`, `Documents/fallout2.cfg`

### Seeder pattern (`iOSSeedDocumentsFromBundle`)
- Runs every launch, idempotent
- `.dat` files → refresh symlinks each launch (bundle path changes on updates)
- `.ini`, config files → copy-once (user edits survive reinstalls)
- Empty `mods_order.txt` deleted so sfall's auto-generator runs

### iCloud savegame sync
- Pull: `NSMetadataQuery` watches cloud scope, slot-atomic copy (all files must be `Current`/`Downloaded`)
- Push: `UIApplicationDidEnterBackground` observer triggers file-level mirror
- Slot tracking via `iOSICloudSlotIsDownloading(slotIndex)` and `iOSICloudConsumeSavesDirty()`

## Build system gotchas (iOS/Xcode)

### CMake POST_BUILD with Xcode
- `VERBATIM` on `add_custom_command` breaks Xcode build-setting expansion (`$<TARGET_BUNDLE_DIR:target>` gets escaped to literal `${...}`)
- Drop `VERBATIM` for any POST_BUILD using generator expressions with `$`

### Xcode archive requirements
- `SKIP_INSTALL=NO` + `INSTALL_PATH=$(LOCAL_APPS_DIR)` required, otherwise `xcodebuild archive` produces empty `.xcarchive`
- Archives fail with `Unknown Distribution Error` if missing

### Bundle ID has two separate sources
- `XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER` (Xcode/code signing)
- `os/ios/Info.plist`'s `CFBundleIdentifier` (CMake-substituted from `MACOSX_BUNDLE_GUI_IDENTIFIER`)
- Both must resolve to the same value — plumbed from `IOS_BUNDLE_IDENTIFIER`

### Per-developer signing
- `ios-signing.cmake` (gitignored) sets `IOS_BUNDLE_IDENTIFIER` + `IOS_DEVELOPMENT_TEAM`
- Use regular variables in the include + `if(NOT DEFINED ...)` in CMakeLists.txt
- `CACHE STRING` with a default is wrong — the default wins silently

### Regen dance after CMake changes
Xcode's "up to date" detection skips POST_BUILD after CMakeLists.txt edits:
```
rm -rf out/build/ios
cmake --preset ios
# then Cmd+Shift+K and Cmd+R in Xcode
```

### Top-level Makefile
- `make ipa`: `cmake --preset ios` → `xcodebuild archive` → `exportArchive`
- Needs `ExportOptions.plist` (in repo) + `ios-signing.cmake` (local)
- Targets: `ipa` (lean, no mods/assets), `mac` (macOS build), `serve` (re-serve IPA over OTA/LAN)

## Codebase navigation hints

### Key files by domain
- **Game loop / UI state**: `src/game.cc`
- **Interface bar**: `src/interface.cc`
- **Mouse input pipeline**: `src/mouse.cc`, `src/game_mouse.cc`
- **Touch handling**: `src/touch.cc`
- **Keyboard**: `src/kb.cc`
- **Input event polling**: `src/input.cc`
- **Settings system**: `src/settings.cc`, `src/settings.h`
- **iOS-specific**: `src/platform/ios/*.mm`
- **Inventory**: `src/inventory.cc`
- **Combat**: `src/combat.cc`
- **Script interpreter**: `src/interpreter*.cc`
- **sfall integration**: `src/sfall_*.cc`
- **Compatibility layer**: `src/platform_compat.cc`

### Cross-platform file I/O
- Always use `compat_fopen`, `compat_gzopen`, `compat_mkdir`, `compat_rename` instead of raw POSIX functions
- These call `compat_windows_path_to_native` (backslash→slash) and `compat_resolve_path` (case resolution)
- Raw `fopen` works on Windows/macOS defaults but breaks on iOS (case-sensitive filesystem)

### iOS UserDefaults integration
- `iOSApplyUserDefaultsToSettings` (`src/platform/ios/paths.mm`) bridges iOS Settings.app to game settings
- Applies after `settingsInit()` reads from `gGameConfig`
- Uses `defaults registerDefaults:` for default values
- New settings added to Settings.bundle need corresponding logic here
- Migrated settings write to `settings.*` struct directly; older ones may still use `configSetInt(&gSfallConfig, ...)`

### Key interaction patterns
- Keyboard handlers in `gameHandleKeyEvent()` guard with `interfaceBarEnabled()` before dispatching to game actions
- Mouse/gesture handlers need to check both `interfaceBarEnabled()` AND `gameUiIsDisabled()` — the keyboard-only pattern is insufficient for touch
- `interfaceBarDisable()` disables buttons but keeps window visible; `interfaceBarHide()` hides the window entirely
- Quick toolbar (`quickToolbarShow/Hide`) is called from `interfaceBarShow/Hide` but NOT from `interfaceBarEnable/Disable`
- Touch gesture recognizer in `src/mouse.cc` handles taps, drags, swipes as discrete gestures mapped to mouse/keyboard events