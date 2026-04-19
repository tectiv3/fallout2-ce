# Talking Heads & Speech System

## Dialog Head Flow
1. Script calls `start_gdialog(headId, reaction, background)` → `opStartGameDialog` in `src/interpreter_extra.cc`
2. `headId` is an index into `art\heads\heads.lst` (loaded by `artInit` in `src/art.cc`)
3. `buildFid(OBJ_TYPE_HEAD, headId, 0, 0, 0)` creates the head FID
4. `_gdialogInitFromScript` → `_gdSetupFidget` loads FRM art and sets up fidget animations
5. Head FID of -1 means "no talking head" → dialog shows text-only

## heads.lst
- Loaded in `artInit()` (`src/art.cc:132`), builds filename array + fidget counts
- Mod loading order: `gameDbInit()` → `sfallLoadMods()` (game.cc:1373) → mods on top of xbase stack → LIFO search means mod's heads.lst wins over master.dat
- Vanilla has 14 entries; Cassidy head mod adds 'casdy' at index 13, pushes 'haku3' to 14

## [Heads] Config Mapping (our addition)
- `ddraw.ini` `[Heads]` section maps critter PID → head index
- Key: `SFALL_CONFIG_HEADS_KEY` in `src/sfall_config.h`
- Logic in `opStartGameDialog`: checks proto `headFid` first, then falls back to ddraw.ini `[Heads]`
- Example: `16777305=13` maps Cassidy (PID 0x1000059) to head index 13

## Speech Playback Path
1. `_scr_get_msg_str_speech` (`src/scripts.cc:2674`) is called during dialog rendering
2. Guard: `FID_TYPE(gGameDialogHeadFid) != OBJ_TYPE_HEAD` → `shouldStartSpeech = 0` (no speech without head)
3. Speech trigger: `messageListItem.audio` field from .msg file must be non-empty
4. Calls `gameDialogStartLips(audioFileName)` (`src/game_dialog.cc:876`)
5. `gameDialogStartLips` → `artCopyFileName(OBJ_TYPE_HEAD, headFid & 0xFFF, name)` to get head name
6. Then `lipsLoad(audioFileName, headName)` (`src/lips.cc:235`)

## Lip Sync & Audio Loading (src/lips.cc)
- `lipsLoad(audioFileName, headFileName)`:
  - Builds path: `SOUND\SPEECH\<headFileName>\<audioBaseName>.<ext>` (ext from `gLipsData.field_60`)
  - Reads .LIP file (version 1 or 2 format) with phoneme data + speech markers
- `_lips_make_speech()` (`src/lips.cc:401`):
  - Builds ACM path: `SOUND\SPEECH\<_lips_subdir_name>\<filename>.ACM`
  - Loads via `soundAllocate(SOUND_TYPE_MEMORY, SOUND_16BIT)` → `soundLoad()`
- `lipsStart()`: sets position, volume, calls `soundPlay(gLipsData.sound)`

## Message File Audio Fields
- .msg format: `{num}{audio}{text}` per line
- Loaded by `messageListLoad` (`src/message.cc:217`)
- Vanilla Cassidy .msg has empty audio fields (no talking head originally)
- Voice mods must provide modified .msg files with audio filenames populated

## Key Files
- `src/interpreter_extra.cc` — `opStartGameDialog` (script opcode handler)
- `src/game_dialog.cc` — dialog rendering, fidget animations, `gameDialogStartLips`
- `src/scripts.cc` — `_scr_get_msg_str_speech` (speech trigger logic)
- `src/lips.cc` — lip sync + ACM audio loading/playback
- `src/art.cc` — `artInit`, `artBuildFilePath`, `artGetFidgetCount`
- `src/message.cc` — .msg file loading with audio field parsing

## Cassidy-Specific
- Critter PID: `0x1000059` = 16777305 decimal
- Head index in modded heads.lst: 13 (filename: 'casdy')
- Head mod: `cassidy_head.dat` — FRM art + modified heads.lst only
- Voice mod: `cassidy_voice_joey_bracken_hq.dat` — ACM + LIP + TXT under `sound\speech\casdy\`
- Both mods designed for UPU/RPU which ship patched dialog scripts
