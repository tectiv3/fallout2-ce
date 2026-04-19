# Settings system

## Architecture

`src/settings.h` defines `Settings` struct with sub-structs: `SystemSettings`, `ScreenSettings`, `UISettings`, `PreferencesSettings`, `SoundSettings`, `DebugSettings`, `QolSettings`, `MapperSettings`. Global instance: `fallout::settings`.

`src/settings.cc` registers every field into a `settingsRegistry` via macros:

- `SETTING(f)` — reads/writes `settings.SECT.f` from/to `gGameConfig` (fallout2.cfg), section name = sub-struct name
- `SETTING_P(f, postProcessor)` — same with a post-processor (e.g. `clamp`, `normalizePath`)
- `SETTING_PATH(f)` — reads `settings.SECT.f##_path`, runs `normalizePath` (strips quotes, converts backslashes, resolves case)

`settingsInit()` flow: `initSettingsRegistry()` → `gameConfigInit()` → read all registered fields from config → `iOSApplyUserDefaultsToSettings()` (iOS only).

`settingsSave()` / `settingsExit()`: write all fields back to `gGameConfig`, then save config to disk.

## Two config files still alive

- **`gGameConfig`** (`fallout2.cfg`): primary config. The settings registry reads from and writes to this. Sections map 1:1 to sub-struct names (`system`, `screen`, `ui`, `preferences`, `sound`, `debug`, `qol`, `mapper`).
- **`gSfallConfig`** (`ddraw.ini`): legacy sfall config. Some settings still read from here at init time (e.g. `DamageFormula` in `combat.cc:6703`). Being progressively migrated out — new settings should go in the `Settings` struct, not `gSfallConfig`.

## Migration from sfall config → Settings struct

Settings are being actively migrated from `gSfallConfig` (ddraw.ini) to the `Settings` struct (fallout2.cfg). When a setting migrates:

1. Add field to the appropriate sub-struct in `settings.h`
2. Register it with `SETTING`/`SETTING_P`/`SETTING_PATH` in `settings.cc`
3. Remove the `SFALL_CONFIG_*_KEY` constant from `sfall_config.h`
4. Update consumers to read from `settings.*` instead of `configGet*(&gSfallConfig, ...)`

**Recent migrations** (constants removed): `SkipOpeningMovies` → `settings.ui.skip_opening_movies`, `DisplayBonusDamage` → `settings.ui.display_bonus_damage`.

**Still in gSfallConfig**: `DamageFormula` (read by `combat.cc` at `combatInit` time), plus various script/mod-related keys.

When writing iOS UserDefaults overrides, use the `settings.*` struct for migrated settings, not `configSetInt(&gSfallConfig, ...)` — the old constants may no longer exist.

## Adding a new setting

1. Add field to the appropriate sub-struct in `settings.h` with a sensible default
2. In `settings.cc`, under the `#define SECT <subsection>` block, add `SETTING(f)` or `SETTING_P(f, clamp(lo, hi))` or `SETTING_PATH(f)` if it's a path
3. The setting automatically reads from `fallout2.cfg` at init and writes back on exit

## normalizePath post-processor

Applied to all `_path` fields. Strips surrounding quotes (shell-style, users add them for paths with spaces like `~/Library/Mobile Documents/...`), then calls `compat_windows_path_to_native` + `compat_resolve_path`. This means path settings in fallout2.cfg can use forward slashes or backslashes and will be normalized.
