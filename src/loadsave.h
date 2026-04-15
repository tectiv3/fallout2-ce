#ifndef LOAD_SAVE_GAME_H
#define LOAD_SAVE_GAME_H

namespace fallout {

typedef enum LoadSaveMode {
    // Special case - loading game from main menu.
    LOAD_SAVE_MODE_FROM_MAIN_MENU,

    // Normal (full-screen) save/load screen.
    LOAD_SAVE_MODE_NORMAL,

    // Quick load/save.
    LOAD_SAVE_MODE_QUICK,
} LoadSaveMode;

void _InitLoadSave();
void _ResetLoadSave();
int lsgSaveGame(int mode);
int lsgLoadGame(int mode);
bool _isLoadingGame();
void lsgInit();

// Pre-position the load/save UI cursor on a given slot (0-based). Used by the
// --load-slot CLI arg so the auto-injected ENTER lands on the right entry.
void lsgSetSlotCursor(int slot);
int MapDirErase(const char* path, const char* extension);
int _MapDirEraseFile_(const char* relativePath, const char* fileName);

} // namespace fallout

#endif /* LOAD_SAVE_GAME_H */
