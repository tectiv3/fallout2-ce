#include "sfall_callbacks.h"

#include "content_config.h"
#include "critter.h"
#include "debug.h"
#include "display_monitor.h"
#include "interface.h"
#include "object.h"
#include "party_member.h"
#include "script_sound.h"
#include "sfall_config.h"
#include "sfall_script_hooks.h"
#include "stat.h"
#include "stat_defs.h"
#include "worldmap.h"

namespace fallout {

void sfallOnBeforeGameInit()
{
    return;
}

void sfallOnGameInit()
{
    return;
}

void sfallOnAfterGameInit()
{
    return;
}

void sfallOnGameExit()
{
    scriptSoundExit();
    return;
}

void sfallOnGameReset()
{
    scriptSoundReset();
    return;
}

void sfallOnBeforeGameStart()
{
    return;
}

void sfallOnAfterGameStarted()
{
    // Disable Horrigan Patch
    bool isDisableHorrigan = false;
    configGetBool(&gContentConfig, CONTENT_CONFIG_WORLDMAP_SECTION, "disable_horrigan", &isDisableHorrigan);

    if (isDisableHorrigan) {
        gDidMeetFrankHorrigan = true;
    }

    bool autoHealOnLevelUp = false;
    configGetBool(&gSfallConfig, SFALL_CONFIG_MISC_KEY, SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP, &autoHealOnLevelUp);
    if (autoHealOnLevelUp) {
        debugPrint("SFALL: AutoHealOnLevelUp enabled\n");
    }

    // Refresh item art after load, which calls the CALCAPCOST hook if present to
    // display the correct AP cost.
    if (gInterfaceBarWindow != -1) {
        int leftItemAction;
        int rightItemAction;
        interfaceGetItemActions(&leftItemAction, &rightItemAction);
        interfaceUpdateItems(false, leftItemAction, rightItemAction);
    }
}

void sfallOnAfterNewGame()
{
    return;
}

void sfallOnGameModeChange(int exit, int previousGameMode)
{
    scriptHooks_GameModeChange(exit, previousGameMode);
}

void sfallOnLevelUp(Object* critter, int oldLevel, int newLevel)
{
    scriptHooks_OnLevelUp(critter, oldLevel, newLevel);
    debugPrint("\nSFALL: HOOK_ONLEVELUP fired (level %d->%d)\n", oldLevel, newLevel);

    bool autoHeal = false;
    configGetBool(&gSfallConfig, SFALL_CONFIG_MISC_KEY, SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP, &autoHeal);
    if (!autoHeal) {
        return;
    }

    int pcRestored = 0;
    if (gDude != nullptr && !critterIsDead(gDude)) {
        int max = critterGetStat(gDude, STAT_MAXIMUM_HIT_POINTS);
        int cur = critterGetHitPoints(gDude);
        if (cur < max) {
            pcRestored = max - cur;
            critterAdjustHitPoints(gDude, pcRestored);
        }
    }

    int partyHealed = 0;
    for (int i = 0; i < gPartyMemberDescriptionsLength; i++) {
        Object* member = partyMemberFindByPid(gPartyMemberPids[i]);
        if (member == nullptr) continue;
        if (member == gDude) continue;
        if (critterIsDead(member)) continue;
        int max = critterGetStat(member, STAT_MAXIMUM_HIT_POINTS);
        int cur = critterGetHitPoints(member);
        if (cur < max) {
            critterAdjustHitPoints(member, max - cur);
            partyHealed++;
        }
    }

    debugPrint("SFALL: AutoHealOnLevelUp restored %d HP to PC, healed %d party member(s)\n", pcRestored, partyHealed);
}

void sfallOnBeforeGameClose()
{
    return;
}

void sfallOnCombatStart()
{
    return;
}

void sfallOnCombatEnd()
{
    return;
}

void sfallOnBeforeMapLoad()
{
    return;
}

} // namespace fallout
