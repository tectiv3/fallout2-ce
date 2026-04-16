#ifndef SFALL_BEHAVIOURS_H
#define SFALL_BEHAVIOURS_H

#include "obj_types.h"

namespace fallout {

void sfallOnBeforeGameInit();
void sfallOnGameInit();
void sfallOnAfterGameInit();
void sfallOnGameExit();
void sfallOnGameReset();
void sfallOnBeforeGameStart();
void sfallOnAfterGameStarted();
void sfallOnAfterNewGame();
void sfallOnGameModeChange(int exit, int previousGameMode);
void sfallOnBeforeGameClose();
void sfallOnCombatStart();
void sfallOnCombatEnd();
void sfallOnBeforeMapLoad();
void sfallOnLevelUp(Object* critter, int oldLevel, int newLevel);

} // namespace fallout

#endif // SFALL_BEHAVIOURS_H
