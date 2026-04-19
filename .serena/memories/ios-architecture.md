# iOS architecture

## Bundle vs Documents split

The iOS build bundles only mods + default configs; the user supplies the heavy data files. Trying to bundle everything blew the IPA past 900MB and duplicated what users already own.

- **Bundled in `.ipa`** (built from `files/`): `fallout2.cfg`, `ddraw.ini`, `f2_res.ini`, `files/mods/` (both `.dat` and `.ini`). CMake POST_BUILD rsyncs these into `$<TARGET_BUNDLE_DIR>/` + `mods/`.
- **User-supplied via Files app into Documents**: `master.dat`, `critter.dat`, `data/` tree (especially `data/sound/music/*.acm` which is NOT inside `master.dat`).
- **Writable / state**: `Documents/data/SAVEGAME/`, `Documents/data/MAPS/`, `Documents/data/proto/`, `Documents/mods/*.ini` (sfall writeback), `Documents/fallout2.cfg`.

`UIFileSharingEnabled = true` in `os/ios/Info.plist` — required for Finder → iPad → Files → app-name access.

## CWD must be Documents, never the bundle

`src/win32.cc` chdir's to `iOSGetDocumentsPath()` before SDL init. The game uses relative paths from CWD everywhere (saves, automap, config writebacks, mods_order.txt, sfall writebacks). The app bundle is read-only and code-signed — any `fopen(..., "w")` inside it is denied by iOS. Do NOT move CWD into the bundle even partially.

## Seeder (`iOSSeedDocumentsFromBundle` in `src/platform/ios/paths.mm`)

Runs every launch, idempotent:
- `mkdir -p Documents/mods`, `Documents/data`, `Documents/data/savegame`
- For each bundled file, either refresh-symlink or copy-once based on intended mutability:
  - `.dat` in mods → **refresh symlink** each launch (bundle path can change on app updates; symlink only replaced if existing entry is also a symlink, never clobbers a user-placed regular file)
  - `.ini`, `fallout2.cfg`, `ddraw.ini`, `f2_res.ini`, `mods_order.txt` → **copy-once** (user edits must survive reinstalls)
- Empty `mods_order.txt` (0 bytes) is deleted each launch so sfall's auto-generator runs.

## The fallout2.cfg absolute-path trap

The game rewrites `fallout2.cfg` on exit with its current settings. If you launch once with a cfg that has absolute paths from a dev machine (e.g. `master_dat=/Users/.../master.dat`), those get baked back in. Pristine `files/fallout2.cfg` must use relative paths. The seeder's copy-once means a user with a previously-corrupted cfg needs to delete `Documents/fallout2.cfg` via Files app to reseed — the app can't force-replace without nuking their customizations.

## iOSApplyUserDefaultsToSettings (src/platform/ios/paths.mm)

Runs after `settingsInit` reads from `gGameConfig`. Overrides specific settings from NSUserDefaults (iOS Settings bundle):
- Screen resolution (native or WxH preset) + scale → `settings.screen.*`
- `skip_intro_movies` → `settings.ui.skip_opening_movies` (maps bool→0/2)
- `damage_formula` → still written to `gSfallConfig` (combat.cc reads from there)
- `combat_display_bonus_damage` → `settings.ui.display_bonus_damage`
- `quick_toolbar_visible` → `quickToolbarSetEnabled()`
- `allow_respec` → `settings.preferences.allow_respec`

When adding new iOS UserDefaults overrides, check whether the setting has migrated to the `Settings` struct. If so, write to `settings.*` directly — the old `SFALL_CONFIG_*_KEY` constants may no longer exist in `sfall_config.h`.

## Makefile

4 targets: `ipa` (lean — no mods/assets, user supplies data files), `mac` (macOS build + zip), `serve` (re-serve existing IPA over OTA), `clean` (`rm -rf out/build`).

- `ipa` uses `-DIOS_BUNDLE_MODS=OFF -DIOS_BUNDLE_ASSETS=OFF`
- `serve` runs `scripts/serve-ipa.sh` (mkcert LAN + optional Tailscale Funnel)
