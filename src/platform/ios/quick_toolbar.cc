#include "quick_toolbar.h"

#if defined(__APPLE__) && TARGET_OS_IOS

#include <string.h>

#include "../../art.h"
#include "../../color.h"
#include "../../combat.h"
#include "../../draw.h"
#include "../../game.h"
#include "../../input.h"
#include "../../interface.h"
#include "../../skilldex.h"
#include "../../svga.h"
#include "../../text_font.h"
#include "../../window_manager.h"

namespace fallout {

namespace {

constexpr int kSkillButtonCount = 8;
constexpr int kSkillButtonWidth = 36;
constexpr int kSkillButtonHeight = 24;
constexpr int kEndTurnButtonWidth = 38;
constexpr int kEndTurnButtonHeight = 22;
constexpr int kDividerGap = 8;
constexpr int kToolbarHeight = 30;
constexpr int kToolbarBottomMargin = 10;

// Injected into the engine input queue when the end-turn region is tapped.
// Matches the keyCode the belt's gEndTurnButton fires; the combat loop consumes
// it identically regardless of source.
constexpr int kEndTurnKeyCode = 32;

struct SkillEntry {
    int skilldexRc;
    const char* label;
};

constexpr SkillEntry kSkills[kSkillButtonCount] = {
    { SKILLDEX_RC_SNEAK, "SNK" },
    { SKILLDEX_RC_LOCKPICK, "LCK" },
    { SKILLDEX_RC_STEAL, "STL" },
    { SKILLDEX_RC_TRAPS, "TRP" },
    { SKILLDEX_RC_FIRST_AID, "FA" },
    { SKILLDEX_RC_DOCTOR, "DOC" },
    { SKILLDEX_RC_SCIENCE, "SCI" },
    { SKILLDEX_RC_REPAIR, "RPR" },
};

int gToolbarWindow = -1;
int gToolbarX = 0;
int gToolbarY = 0;
int gToolbarWidth = 0;
bool gShown = false;
bool gEndTurnVisible = false;

FrmImage gEndTurnFrm;

int skillButtonX(int index)
{
    return index * kSkillButtonWidth;
}

int endTurnRegionX()
{
    return kSkillButtonCount * kSkillButtonWidth + kDividerGap;
}

void fillRect(unsigned char* buffer, int pitch, int x, int y, int w, int h, unsigned char color)
{
    for (int row = 0; row < h; row++) {
        memset(buffer + (y + row) * pitch + x, color, static_cast<size_t>(w));
    }
}

void drawCenteredLabel(unsigned char* buffer, int pitch, int x, int y, int w, int h, const char* text, unsigned char color)
{
    int textWidth = fontGetStringWidth(text);
    int lineHeight = fontGetLineHeight();
    int tx = x + (w - textWidth) / 2;
    int ty = y + (h - lineHeight) / 2;
    if (tx < x) tx = x;
    if (ty < y) ty = y;
    fontDrawText(buffer + ty * pitch + tx, text, pitch, pitch, color);
}

void paintSkillButton(int index)
{
    unsigned char* buffer = windowGetBuffer(gToolbarWindow);
    if (buffer == nullptr) {
        return;
    }

    int x = skillButtonX(index);
    int y = (kToolbarHeight - kSkillButtonHeight) / 2;

    fillRect(buffer, gToolbarWidth, x, y, kSkillButtonWidth, kSkillButtonHeight, _colorTable[7708]);
    drawCenteredLabel(buffer, gToolbarWidth, x, y, kSkillButtonWidth, kSkillButtonHeight, kSkills[index].label, _colorTable[32747]);
}

void paintEndTurnRegion()
{
    unsigned char* buffer = windowGetBuffer(gToolbarWindow);
    if (buffer == nullptr) {
        return;
    }

    int x = endTurnRegionX();
    int y = (kToolbarHeight - kEndTurnButtonHeight) / 2;

    // Always clear first so leaving combat erases any previously-painted sprite.
    fillRect(buffer, gToolbarWidth, x, y, kEndTurnButtonWidth, kEndTurnButtonHeight, _colorTable[0]);

    if (gEndTurnVisible && gEndTurnFrm.isLocked()) {
        blitBufferToBuffer(gEndTurnFrm.getData(),
            gEndTurnFrm.getWidth(), gEndTurnFrm.getHeight(),
            gEndTurnFrm.getWidth(),
            buffer + y * gToolbarWidth + x,
            gToolbarWidth);
    }
}

void paintDivider()
{
    unsigned char* buffer = windowGetBuffer(gToolbarWindow);
    if (buffer == nullptr) {
        return;
    }

    int x = kSkillButtonCount * kSkillButtonWidth + kDividerGap / 2;
    unsigned char color = gEndTurnVisible ? _colorTable[16895] : _colorTable[0];
    for (int row = 4; row < kToolbarHeight - 4; row++) {
        buffer[row * gToolbarWidth + x] = color;
    }
}

void paintAll()
{
    unsigned char* buffer = windowGetBuffer(gToolbarWindow);
    if (buffer == nullptr) {
        return;
    }

    fillRect(buffer, gToolbarWidth, 0, 0, gToolbarWidth, kToolbarHeight, _colorTable[0]);

    int oldFont = fontGetCurrent();
    fontSetCurrent(101);
    for (int i = 0; i < kSkillButtonCount; i++) {
        paintSkillButton(i);
    }
    fontSetCurrent(oldFont);

    paintDivider();
    paintEndTurnRegion();
}

} // namespace

void quickToolbarInit()
{
    if (gToolbarWindow != -1) {
        return;
    }

    gToolbarWidth = kSkillButtonCount * kSkillButtonWidth + kDividerGap + kEndTurnButtonWidth;
    gToolbarX = (screenGetWidth() - gToolbarWidth) / 2;
    gToolbarY = screenGetHeight() - INTERFACE_BAR_HEIGHT - kToolbarHeight - kToolbarBottomMargin;

    gToolbarWindow = windowCreate(gToolbarX, gToolbarY, gToolbarWidth, kToolbarHeight, _colorTable[0], WINDOW_HIDDEN);
    if (gToolbarWindow == -1) {
        return;
    }

    int endTurnFid = buildFid(OBJ_TYPE_INTERFACE, 105, 0, 0, 0);
    gEndTurnFrm.lock(endTurnFid);

    gEndTurnVisible = isInCombat();
    paintAll();
    windowRefresh(gToolbarWindow);
}

void quickToolbarFree()
{
    if (gToolbarWindow == -1) {
        return;
    }

    windowDestroy(gToolbarWindow);
    gToolbarWindow = -1;
    gShown = false;
    gEndTurnVisible = false;
    gEndTurnFrm.unlock();
}

void quickToolbarShow()
{
    if (gToolbarWindow == -1 || gShown) {
        return;
    }
    windowShow(gToolbarWindow);
    gShown = true;
}

void quickToolbarHide()
{
    if (gToolbarWindow == -1 || !gShown) {
        return;
    }
    windowHide(gToolbarWindow);
    gShown = false;
}

bool quickToolbarIsWindow(int windowId)
{
    return gToolbarWindow != -1 && windowId == gToolbarWindow;
}

void quickToolbarUpdateCombatState()
{
    if (gToolbarWindow == -1) {
        return;
    }

    bool shouldShow = isInCombat();
    if (shouldShow == gEndTurnVisible) {
        return;
    }

    gEndTurnVisible = shouldShow;
    paintDivider();
    paintEndTurnRegion();
    windowRefresh(gToolbarWindow);
}

bool quickToolbarContainsPoint(int x, int y)
{
    if (gToolbarWindow == -1 || !gShown) {
        return false;
    }
    return x >= gToolbarX && x < gToolbarX + gToolbarWidth
        && y >= gToolbarY && y < gToolbarY + kToolbarHeight;
}

bool quickToolbarHandleTap(int x, int y)
{
    if (!quickToolbarContainsPoint(x, y)) {
        return false;
    }

    int localX = x - gToolbarX;

    // Skill region.
    if (localX < kSkillButtonCount * kSkillButtonWidth) {
        int index = localX / kSkillButtonWidth;
        gameHandleSkilldexResult(kSkills[index].skilldexRc);
        return true;
    }

    // End-turn region — only reactive during combat.
    int endX = endTurnRegionX();
    if (gEndTurnVisible && localX >= endX && localX < endX + kEndTurnButtonWidth) {
        enqueueInputEvent(kEndTurnKeyCode);
        return true;
    }

    // Tap landed in the divider gap — consume silently so it doesn't fall
    // through to the game area and trigger a walk command.
    return true;
}

} // namespace fallout

#endif // defined(__APPLE__) && TARGET_OS_IOS
