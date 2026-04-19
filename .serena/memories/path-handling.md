# Path handling — Windows backslashes, case, compat layer

## Backslash paths pervade the engine

Hardcoded paths throughout the codebase use Windows backslashes (`"mods\\*.dat"`, `"data\\MAPS\\AUTOMAP.DB"`, `"%s\\proto"`, etc.). This is carried over from the original Windows game; not a bug.

- sfall mods also use this style: `FO2tweaks/source/*.ssl` has `#define fo2tweaks_ini "mods\\fo2tweaks.ini"`.
- `src/sfall_ini.cc:92` even constructs `%s\\%s` when combining base path and ini name.

## `compat_windows_path_to_native` converts at the fopen boundary

`src/platform_compat.cc:301` — on non-Windows, rewrites `\\` to `/` in-place. Called by every compat file function before touching the actual OS: `compat_fopen`, `compat_gzopen`, `compat_mkdir`, `compat_rename`, etc. Also followed by `compat_resolve_path` which walks the path and resolves case-insensitively on case-sensitive filesystems.

This means **don't add new fopen calls that bypass compat_fopen**. If code is using raw `fopen`, it may work on Windows/macOS default (case-insensitive, slash-agnostic) but break on iOS (case-sensitive) or Linux.

## Path conventions by category

- **Read-only game data files** (`master.dat`, `critter.dat`, `mods/*.dat`): opened by the dfile/dbase layer via `compat_fopen`. Paths come from `settings.system.master_dat_path` etc. or hardcoded relative paths like `"mods\\*.dat"`.
- **Patches / writable game data** (`data/SAVEGAME`, `data/MAPS`, `data/proto`): live under `settings.system.master_patches_path` (defaults to `"data"`).
- **User configs**: `fallout2.cfg` (game_config.cc), `ddraw.ini` + `f2_res.ini` (sfall_config.cc / sfall_ini.cc system file list), mod inis in `mods/*.ini`.

## iOS path specifics

- CWD is set to Documents (trailing slash) in `src/win32.cc` via `chdir(iOSGetDocumentsPath())`. Every relative path in the codebase resolves from there.
- iOS filesystem is case-sensitive. Data files must match the expected case (typically lowercase `master.dat`).
- Paths like `/var/mobile/Containers/Data/Application/<UUID>/Documents/` change UUID on app updates — the bundle path changes too. Anything that caches absolute paths (e.g. the fallout2.cfg writeback) will become stale.
