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
constexpr int kButtonWidth = 36;
constexpr int kButtonHeight = 24;
constexpr int kDividerGap = 8;
constexpr int kToolbarHeight = 30;
constexpr int kToolbarBottomMargin = 10;

// Matches gEndTurnButton's keyCode in interface.cc — the combat loop's input
// dispatch consumes 32 as end-turn regardless of where it originated.
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

int toolbarWidthFor(bool endTurnVisible)
{
    int width = kSkillButtonCount * kButtonWidth;
    if (endTurnVisible) {
        width += kDividerGap + kButtonWidth;
    }
    return width;
}

int endTurnButtonX()
{
    return kSkillButtonCount * kButtonWidth + kDividerGap;
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

// Dark panel with a soft highlight on top/left and shadow on bottom/right so
// buttons read as raised without dominating the frame. Palette entries are
// sampled from the intensity table of white so they stay consistent with the
// game's palette across lighting changes.
void paintPanelButton(unsigned char* buffer, int pitch, int x, int y, int w, int h, const char* label)
{
    unsigned char panel = intensityColorTable[_colorTable[32767]][22];
    unsigned char highlight = intensityColorTable[_colorTable[32767]][55];
    unsigned char shadow = _colorTable[0];

    fillRect(buffer, pitch, x, y, w, h, panel);
    fillRect(buffer, pitch, x, y, w, 1, highlight);
    fillRect(buffer, pitch, x, y, 1, h, highlight);
    fillRect(buffer, pitch, x, y + h - 1, w, 1, shadow);
    fillRect(buffer, pitch, x + w - 1, y, 1, h, shadow);

    drawCenteredLabel(buffer, pitch, x, y, w, h, label, _colorTable[32747]);
}

void paintDivider(unsigned char* buffer)
{
    int x = kSkillButtonCount * kButtonWidth + kDividerGap / 2;
    for (int row = 4; row < kToolbarHeight - 4; row++) {
        buffer[row * gToolbarWidth + x] = _colorTable[16895];
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

    int buttonY = (kToolbarHeight - kButtonHeight) / 2;
    for (int i = 0; i < kSkillButtonCount; i++) {
        paintPanelButton(buffer, gToolbarWidth, i * kButtonWidth, buttonY, kButtonWidth, kButtonHeight, kSkills[i].label);
    }

    if (gEndTurnVisible) {
        paintDivider(buffer);
        paintPanelButton(buffer, gToolbarWidth, endTurnButtonX(), buttonY, kButtonWidth, kButtonHeight, "END");
    }

    fontSetCurrent(oldFont);
}

// The toolbar window is sized to whatever content is currently visible so the
// black window background never bleeds into an "empty" end-turn slot. A combat
// state flip therefore destroys and recreates the window at the new size.
void createWindow()
{
    gToolbarWidth = toolbarWidthFor(gEndTurnVisible);
    gToolbarX = (screenGetWidth() - gToolbarWidth) / 2;
    gToolbarY = screenGetHeight() - INTERFACE_BAR_HEIGHT - kToolbarHeight - kToolbarBottomMargin;

    gToolbarWindow = windowCreate(gToolbarX, gToolbarY, gToolbarWidth, kToolbarHeight, _colorTable[0], WINDOW_HIDDEN);
    if (gToolbarWindow == -1) {
        return;
    }

    paintAll();
}

void destroyWindow()
{
    if (gToolbarWindow == -1) {
        return;
    }
    windowDestroy(gToolbarWindow);
    gToolbarWindow = -1;
}

} // namespace

void quickToolbarInit()
{
    if (gToolbarWindow != -1) {
        return;
    }
    gEndTurnVisible = isInCombat();
    createWindow();
}

void quickToolbarFree()
{
    destroyWindow();
    gShown = false;
    gEndTurnVisible = false;
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
    bool shouldShow = isInCombat();
    if (shouldShow == gEndTurnVisible && gToolbarWindow != -1) {
        return;
    }

    bool wasShown = gShown;
    destroyWindow();
    gShown = false;
    gEndTurnVisible = shouldShow;
    createWindow();
    if (wasShown) {
        quickToolbarShow();
    }
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

    if (localX < kSkillButtonCount * kButtonWidth) {
        int index = localX / kButtonWidth;
        gameHandleSkilldexResult(kSkills[index].skilldexRc);
        return true;
    }

    int endX = endTurnButtonX();
    if (gEndTurnVisible && localX >= endX && localX < endX + kButtonWidth) {
        enqueueInputEvent(kEndTurnKeyCode);
        return true;
    }

    // Tap landed in the divider gap — consume silently so it doesn't fall
    // through to the game area and trigger a walk command.
    return true;
}

} // namespace fallout

#endif // defined(__APPLE__) && TARGET_OS_IOS
