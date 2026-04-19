# Savegame path handling

## Configuration

`settings.system.savegame_path` — defaults to `"SAVEGAME"`. Registered as a `SETTING_PATH` so it gets `normalizePath` treatment (quote stripping, backslash conversion, case resolution).

## Two path helpers in loadsave.cc

- **`lsgSavegameDir()`**: returns the raw `savegame_path` value (or `"SAVEGAME"` if empty). Used for xfile-mediated paths where the engine prepends `master_patches_path` automatically.
- **`lsgSavegameRoot()`**: returns the full physical path. If `savegame_path` is absolute (starts with `/` or `\`), returns it as-is. Otherwise prepends `_patches` (which is `settings.system.master_patches_path`) + `\\` + dir. Used for raw POSIX I/O that doesn't go through xbase.

Default: `lsgSavegameRoot()` = `data\SAVEGAME` (relative from CWD).

## Absolute path redirect

Set `savegame_path` to an absolute path in `fallout2.cfg` to redirect saves elsewhere (e.g. iCloud Drive's ubiquity container for Mac↔iPad sync). Both helpers converge to the same location regardless.

## iOS iCloud savegame sync

`src/platform/ios/paths.mm` mirrors `Documents/data/savegame` ↔ iCloud Drive ubiquity container. Pull driven by `NSMetadataQuery` (slot-atomic, tracks placeholder downloads). Push registered as `UIApplicationDidEnterBackground` observer. Safe to call when iCloud unavailable (no-op).

- `iOSICloudSlotIsDownloading(slotIndex)` — check if a cloud slot is still downloading
- `iOSICloudConsumeSavesDirty()` — one-shot flag, polled by load/save menu to refresh slot status

## Seeder creates savegame dir

`iOSSeedDocumentsFromBundle` does `mkdir -p Documents/data/savegame` every launch.
