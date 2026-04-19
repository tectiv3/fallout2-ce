#ifndef SFALL_CONFIG_H
#define SFALL_CONFIG_H

#include "config.h"

namespace fallout {

#define SFALL_CONFIG_FILE_NAME "ddraw.ini"

#define SFALL_CONFIG_MAIN_KEY "Main"
#define SFALL_CONFIG_MISC_KEY "Misc"
#define SFALL_CONFIG_SCRIPTS_KEY "Scripts"
#define SFALL_CONFIG_HEADS_KEY "Heads"

#define SFALL_CONFIG_OVERRIDE_CRITICALS_MODE_KEY "OverrideCriticalTable"
#define SFALL_CONFIG_OVERRIDE_CRITICALS_FILE_KEY "OverrideCriticalFile"
#define SFALL_CONFIG_BOOKS_FILE_KEY "BooksFile"
#define SFALL_CONFIG_ELEVATORS_FILE_KEY "ElevatorsFile"
#define SFALL_CONFIG_UNARMED_FILE_KEY "UnarmedFile"
#define SFALL_CONFIG_INI_CONFIG_FOLDER "IniConfigFolder"
#define SFALL_CONFIG_CONFIG_FILE "ConfigFile"
#define SFALL_CONFIG_PATCH_FILE "PatchFile"
#define SFALL_CONFIG_PATCH_FILE "PatchFile"
#define SFALL_CONFIG_CITIES_LIMIT_FIX "CitiesLimitFix"
#define SFALL_CONFIG_PIPBOY_AVAILABLE_AT_GAMESTART "PipBoyAvailableAtGameStart"
#define SFALL_CONFIG_WORLDMAP_TRAIL_MARKERS "WorldMapTravelMarkers"
#define SFALL_CONFIG_DISABLE_HORRIGAN "DisableHorrigan"
#define SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP "AutoHealOnLevelUp"

#define SFALL_CONFIG_BURST_MOD_DEFAULT_CENTER_MULTIPLIER 1
#define SFALL_CONFIG_BURST_MOD_DEFAULT_CENTER_DIVISOR 3
#define SFALL_CONFIG_BURST_MOD_DEFAULT_TARGET_MULTIPLIER 1
#define SFALL_CONFIG_BURST_MOD_DEFAULT_TARGET_DIVISOR 2

extern bool gSfallConfigInitialized;
extern Config gSfallConfig;

bool sfallConfigInit(int argc, char** argv);
void sfallConfigExit();

} // namespace fallout

#endif /* SFALL_CONFIG_H */
