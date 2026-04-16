# Auto-heal on level-up + `HOOK_ONLEVELUP`

**Date:** 2026-04-16
**Status:** Design approved, awaiting implementation plan
**Scope:** Single engine change delivering two linked features: a new sfall hook and its first consumer.

## Summary

Add two linked features to fallout2-ce:

1. **`HOOK_ONLEVELUP`** — a new notification-only sfall hook (ID `100`, in the fallout2-ce-local extension range) that fires once per PC level gained, with args `(critter, old_level, new_level)`. Reusable extension point for mods.
2. **Auto-heal-on-level-up** — a built-in gameplay tweak gated by `[Misc] AutoHealOnLevelUp=1` in `ddraw.ini` (default `0`). When enabled, tops off the PC and every living party member to their max HP after a level-up batch resolves.

Both land in one change. The auto-heal feature does **not** consume the hook internally — it calls its own engine-side function at the same injection site. The hook is purely the public API for sfall scripts.

## Motivation

- Users want the option to remove the friction of "level up → walk to a bed or pop stimpaks" after gaining power, especially in late-game where HP pools outrun portable healing.
- sfall does not expose a level-up hook (verified against `sfall-team/sfall@master` `HookScripts.h`, `hooks.yml`, bgforge docs, and the `PartyMemberNonRandomLevelUp` option). BGforge's `FO2tweaks/source/gl_g_party_level_match.ssl` polls `HOOK_GAMEMODECHANGE` *because* no level hook exists — confirmation of the gap.
- Adding the hook now unblocks future mods (quest-on-level, auto-save-on-level, scripted perks tied to level) without another round of engine edits.

## Non-goals

- Restoring crippled limbs, poison, radiation, or drug effects. HP-only.
- Auto-distributing skill points or picking perks.
- Modifying the HP-per-level formula (that would be a sibling `HOOK_BEFORELEVELUP`, explicitly out of scope for v1).
- Firing the hook for party members — v1 is PC-only. Future extension (see §8).
- Healing dead party members (resurrection is a different feature).
- Compatibility with vanilla sfall scripts that expect their own non-existent level hook — ours is a new public ID for fallout2-ce.

## Architecture

Two decoupled pieces, both living in the sfall integration layer:

```
   ┌───────────────────────────────────────┐
   │ stat.cc pcAddExperienceWithOptions   │
   │  while (level < MAX):                 │
   │    level++                            │
   │    apply HP bonus                     │
   │    refresh HP UI                      │
   │    _partyMemberIncLevels()            │
   │    ├─► scriptHooks_OnLevelUp()  ──────┼──► HOOK_ONLEVELUP (public API)
   │    └─► leveledUp = true               │       ▼
   │                                       │    [any registered .ssl scripts]
   │  if leveledUp:                        │
   │    callbacks_AutoHealOnLevelUp() ─────┼──► heals gDude + party if
   │                                       │    AutoHealOnLevelUp=1 in ddraw.ini
   └───────────────────────────────────────┘
```

The hook fires at the end of each level-up iteration, after all synchronous per-level side effects (HP bonus, UI refresh, item-action update, party propagation) have been applied. Scripts therefore observe a fully-committed state: PC level/max-HP/current-HP updated, party members at their new levels, UI in sync.

**Rationale for separation:**
- The hook is a notification API — fire it whether or not auto-heal is enabled, so scripts get the signal unconditionally.
- Auto-heal is a C++ engine feature. Making it "subscribe" to its own hook would require bridging to the sfall script dispatcher (expects `.int` script procs) — more code, harder to reason about, no functional benefit.
- Keeping them side-by-side at the same injection site is simple and keeps each concern isolated.

## Hook design — `HOOK_ONLEVELUP`

| Field | Value |
|---|---|
| Name | `HOOK_ONLEVELUP` (matches `HOOK_ONDEATH` naming pattern) |
| Enum ID | `100` — first slot in the fallout2-ce-local extension range. See §"Why ID 100" below. |
| Arg 0 | `Object* critter` — the PC (always `gDude` in v1) |
| Arg 1 | `int old_level` — level value *before* this level-up iteration |
| Arg 2 | `int new_level` — level value *after* this level-up iteration |
| Return | none (notification-only, `maxReturnValues = 0` in `ScriptHookCall`) |
| Fire point | `src/stat.cc` inside `pcAddExperienceWithOptions`, at the end of the level-up `if`-block — after `_partyMemberIncLevels()` (~line 792), so scripts see the fully-committed post-level-up state |
| Trigger condition | Only fires on successful forward level progression (`pcSetStat(PC_STAT_LEVEL, old+1) == 0`). Level decreases via `pcSetExperience` (xp rollback) do **not** fire the hook and do **not** trigger auto-heal. |
| Frequency | Once per level gained. A multi-level XP grant fires the hook N times. |

### Why ID 100

The original fork author reserved `49..60` for future upstream sfall hook additions (see the `// RESERVED 49..60` comment in `sfall_script_hooks.h:149`). Since then, upstream sfall continues to add hooks sequentially without gap-filling, so any ID chosen just above the last synced upstream slot (currently `HOOK_BUILDSFXWEAPON = 61`) is at risk of colliding with a future upstream hook, forcing a renumber and breaking any scripts that hard-coded the integer.

The principled fix is to establish a **dedicated fallout2-ce-local range**. This spec widens the existing reservation comment to:

```cpp
// RESERVED 49..99: upstream sfall parity slots (past & future).
// 100+: fallout2-ce-local hook extensions.
```

`HOOK_ONLEVELUP = 100` is the first entry in that local range. Any future fallout2-ce-specific hooks (e.g., a hypothetical `HOOK_BEFORELEVELUP`) take `101`, `102`, etc. Upstream sfall is free to add hooks up to `99` without conflict. This is a deliberate one-time enum gap — memory cost is `8 * ~40 unused slots ≈ 300 bytes` in the hook array, negligible.

### Why fire at end of iteration (after party propagation)

Scripts asking `get_critter_stat(dude, STAT_max_hp)`, `get_critter_stat(dude, STAT_current_hp)`, or any party-member level inside the hook see a **fully committed** state: PC HP bonus applied, HP UI refreshed, item-actions updated, and party members already at their matched level. Firing earlier (next to the sound, or next to the HP adjust) would expose mid-transaction state where some of those values are stale — a latent WAT for script authors.

The sound effect (`soundPlayFile("levelup")` at ~line 769) is deliberately upstream of the hook. It is user-facing feedback, not script infrastructure; script coherence matters more than cosmetic adjacency.

If a script mutates HP inside the hook, it must call its own interface refresh — the engine's `interfaceRenderHitPoints` call at ~line 783 has already happened by the time the hook fires. Document this in the hook's help text.

### Why notification-only (no return value)

Our fire point is **after** engine state is committed. A script return value like "modified HP delta" is semantically wrong here — the HP is already applied. Adding an ignored return slot would mislead script authors into thinking they can modify state. If modification ever becomes a requirement, the correct answer is a sibling `HOOK_BEFORELEVELUP` (ID `101`, next slot in the fallout2-ce-local range) at a different call-site (before `critterAdjustHitPoints`), mirroring the sfall `HOOK_STDPROCEDURE` / `HOOK_STDPROCEDURE_END` split.

## Auto-heal feature design

### Config

Follows the `SFALL_CONFIG_DISABLE_HORRIGAN` template exactly:

- `src/sfall_config.h` — `#define SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP "AutoHealOnLevelUp"`
- `src/sfall_config.cc` — `configSetBool(&gSfallConfig, SFALL_CONFIG_MISC_KEY, SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP, false);`
- `files/ddraw.ini` `[Misc]` — add commented-off entry:
  ```ini
  ; Top off PC and party member HP to max when the PC levels up.
  ; 0=off (default), 1=on.
  ;AutoHealOnLevelUp=0
  ```

Default `false` chosen so upgrading users don't get a silent behavior change.

### Heal logic

New function `callbacks_AutoHealOnLevelUp()` in `src/sfall_callbacks.cc` / `.h` (category match: sits alongside `DisableHorrigan` and other sfall-style gameplay toggles):

```cpp
void callbacks_AutoHealOnLevelUp()
{
    bool enabled = false;
    configGetBool(&gSfallConfig, SFALL_CONFIG_MISC_KEY,
                  SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP, &enabled);
    if (!enabled) return;

    // Heal PC.
    if (gDude != nullptr && !critterIsDead(gDude)) {
        int max = critterGetStat(gDude, STAT_MAXIMUM_HIT_POINTS);
        int cur = critterGetHitPoints(gDude);
        if (cur < max) {
            critterAdjustHitPoints(gDude, max - cur);
        }
    }

    // Heal every living party member.
    for (int i = 0; i < gPartyMemberDescriptionsLength; i++) {
        Object* member = partyMemberFindByPid(gPartyMemberPids[i]);
        if (member == nullptr) continue;          // dismissed/absent
        if (member == gDude) continue;            // PC already handled
        if (critterIsDead(member)) continue;      // dead stays dead
        int max = critterGetStat(member, STAT_MAXIMUM_HIT_POINTS);
        int cur = critterGetHitPoints(member);
        if (cur < max) {
            critterAdjustHitPoints(member, max - cur);
        }
    }
}
```

Party iteration idiom mirrors existing uses in `src/perk.cc:255-287` and `src/combat_ai.cc:576-598`. `partyMemberFindByPid` + null-check handles the "registered but not currently in party" case (e.g., slot 0 might be Sulik, who is elsewhere).

### Runs once per level-up batch, not per level

Auto-heal is called **outside** the while loop in `pcAddExperienceWithOptions`, gated by a `leveledUp` bool that flips to true on any successful level increment. Healing to max is idempotent, so running once after the batch saves redundant work while still covering any number of level gains in a single XP grant.

### Rollback paths do not trigger auto-heal

`pcSetExperience` (`stat.cc:805`) sets PC level directly from an XP value without going through the level-up while-loop. This is used by XP-rollback / debug paths and can *decrease* level. It does **not** fire `HOOK_ONLEVELUP` and does **not** trigger auto-heal. This matches the "on level up" semantics — rolling back is not leveling up.

## Injection points — `src/stat.cc`

Minimal diff in `pcAddExperienceWithOptions` (~lines 734-802). Additions are marked with `// NEW` — everything else byte-identical to current source:

```cpp
int pcAddExperienceWithOptions(int xp, bool doParty, int* xpGained)
{
    // ...lines 736-750 unchanged (XP clamp & assign)...
    gPcStatValues[PC_STAT_EXPERIENCE] = newXp;

    bool leveledUp = false;                                   // NEW

    while (gPcStatValues[PC_STAT_LEVEL] < PC_LEVEL_MAX) {
        if (newXp < pcGetExperienceForNextLevel()) {
            break;
        }

        int oldLevel = gPcStatValues[PC_STAT_LEVEL];          // NEW (pre-bump)

        // pcSetStat returns 0 on successful stat write. This is the
        // invariant we rely on to know the level actually advanced.
        if (pcSetStat(PC_STAT_LEVEL, oldLevel + 1) == 0) {
            int newLevel = gPcStatValues[PC_STAT_LEVEL];      // NEW (post-bump)
            int maxHpBefore = critterGetStat(gDude, STAT_MAXIMUM_HIT_POINTS);

            // ...lines 761-781 unchanged — that block computes `hpPerLevel`,
            // updates `STAT_MAXIMUM_HIT_POINTS` bonus, derives `maxHpAfter`,
            // then applies the delta. Unmodified.
            critterAdjustHitPoints(gDude, maxHpAfter - maxHpBefore);
            interfaceRenderHitPoints(false);
            // ...lines 786-789 unchanged (item actions)...

            if (doParty) {
                _partyMemberIncLevels();
            }

            scriptHooks_OnLevelUp(gDude, oldLevel, newLevel); // NEW (fire hook — state fully committed)
            leveledUp = true;                                 // NEW
        }
    }

    if (leveledUp) {
        callbacks_AutoHealOnLevelUp();                        // NEW (one heal pass)
    }

    if (xpGained != nullptr) {
        *xpGained = newXp - oldXp;
    }

    return 0;
}
```

Observable behavior for users with `AutoHealOnLevelUp=0` and no `HOOK_ONLEVELUP` subscribers: byte-identical to today. The hook dispatch with zero registered scripts is a handful of instructions; the auto-heal function short-circuits on the disabled flag before touching any critter.

## Files touched

| # | File | Change |
|---|---|---|
| 1 | `src/sfall_config.h` | `+#define SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP "AutoHealOnLevelUp"` |
| 2 | `src/sfall_config.cc` | `configSetBool(..., SFALL_CONFIG_AUTO_HEAL_ON_LEVELUP, false);` alongside other `[Misc]` defaults |
| 3 | `src/sfall_script_hooks.h` | Widen the `// RESERVED 49..60` comment to `// RESERVED 49..99: upstream sfall parity slots` and add an adjacent `// 100+: fallout2-ce-local hook extensions` note; add `HOOK_ONLEVELUP = 100` before `HOOK_COUNT`; declare `scriptHooks_OnLevelUp` |
| 4 | `src/sfall_script_hooks.cc` | Implement `scriptHooks_OnLevelUp` (3-line body + docblock, mirrors `scriptHooks_OnDeath`) |
| 5 | `src/sfall_callbacks.h` | Declare `void callbacks_AutoHealOnLevelUp();` |
| 6 | `src/sfall_callbacks.cc` | Implement `callbacks_AutoHealOnLevelUp()` as shown above |
| 7 | `src/stat.cc` | Injection in `pcAddExperienceWithOptions` as shown above |
| 8 | `files/ddraw.ini` | Add commented `;AutoHealOnLevelUp=0` under `[Misc]` |

Zero new files. No changes to save format, CMake, build presets, or iOS bundling.

## Edge cases

| Case | Behavior |
|---|---|
| Setting absent from ddraw.ini | `configGetBool` leaves output untouched → defaults to `false`. Feature disabled for existing users on upgrade. |
| gDude is dead | `critterIsDead(gDude)` check in the heal function short-circuits defensively, even though reaching this path via normal XP grant is not expected. |
| Multi-level XP grant (50k XP, 3 levels at once) | While loop iterates 3 times. Hook fires 3 times (once per level). Auto-heal runs once after the loop. Idempotent. |
| Party member is dead | Skipped by `critterIsDead(member)` check. |
| Party member unconscious/prone | HP healed, state unchanged. Waking them is a separate concern. |
| Party slot registered but member absent | `partyMemberFindByPid` returns `nullptr` → skipped. |
| Party member already at full HP | `cur < max` guard → no-op. |
| HP would overflow max | `critterAdjustHitPoints` clamps (critter.cc:~307). Safe. |
| Level-up during combat | Hook fires, auto-heal runs. Known interaction; user opted in. Not guarding — adding a "not during combat" gate is complex and unexpected for someone who toggled the flag. Tested in §Testing step 7 against animation/state desync. |
| sfall script registered for `HOOK_ONLEVELUP` throws an error | Existing dispatcher behavior: sfall logs, other subscribers continue. No engine state corruption. |
| sfall script grants XP inside its own `HOOK_ONLEVELUP` callback (recursive level-up) | `ScriptHookCall` has `MAX_HOOK_CALL_DEPTH = 8` (`sfall_script_hooks.cc:~24`). Recursive hook calls beyond that depth are rejected by the dispatcher. No stack blowup. |
| Save/load mid-level-up | No save format changes; no migration. `DUDE_STATE_LEVEL_UP_AVAILABLE` (set at `stat.cc:767`) is intentionally left alone — perk-screen flow clears it; auto-heal doesn't. |
| PC hits `PC_LEVEL_MAX` | While-loop terminates normally. No special handling needed. |
| XP rollback (`pcSetExperience` with lower value) | Bypasses the while loop entirely. Hook does not fire; auto-heal does not run. Intended — "on level up" ≠ "on level down". |

## Testing

No unit test harness exists in the repo (fallout2-ce is integration-tested by playing). Validation plan:

**Build gate:**
- `cmake --preset macos-arm64 && cmake --build out/build/macos-arm64` — catches signatures, linkage, missing includes.

**Manual, using `--load-slot` harness** (added in commit `b35a4245`):

1. **Setting off (default):** `AutoHealOnLevelUp=0` or unset. Load save, grant XP, confirm HP **not** topped off, HP-per-level bonus still works.
2. **Setting on:** set `AutoHealOnLevelUp=1`, reload. Grant XP. Confirm PC HP = max **and** every living party member HP = max. Max HP should still have grown by the standard per-level bonus.
3. **Multi-level jump:** grant XP sufficient to skip 3 levels in one call. Confirm HP ends at max, not mid-bonus.
4. **Party edge cases:** dismiss a party member, level up. Confirm no crash, remaining members heal.
5. **Pre-party game:** start new game pre-Arroyo, level up. Confirm no crash with empty party.
6. **Hook wiring:** temporarily add an `SDL_Log("HOOK_ONLEVELUP fired: %p %d→%d", critter, oldLevel, newLevel);` at the top of `scriptHooks_OnLevelUp`. Build, level up, confirm the log line appears once per level gained with correct values. Remove the log before merge. (Dropping a compiled `.int` into `data/scripts/` would require an SSL toolchain the repo doesn't document; a temporary printf exercises the same dispatch path with zero external deps.)
7. **Combat level-up:** gain enough XP mid-combat to level up (e.g., finish an enemy that pushes the PC across a threshold). Verify: (a) auto-heal fires — PC + living party HP at max after the kill animation resolves; (b) no desync between displayed HP and actual HP; (c) no assertion or animation-glitch in the log; (d) combat turn order/state unaffected; (e) kill animation completes normally.

## Future extensions

Left explicitly out of scope, listed here so the trail is visible:

- `HOOK_BEFORELEVELUP` (ID `101`, next slot in the fallout2-ce-local range) at a pre-HP-bonus fire point, returning a modified HP-per-level delta. Add only when a mod requests it.
- Fire `HOOK_ONLEVELUP` for party members too, from inside `_partyMemberIncLevels`. Requires capturing per-member old/new levels.
- Finer-grained auto-heal scope (uncripple limbs, clear poison/radiation). Each should be a separate `[Misc]` flag, not options of `AutoHealOnLevelUp`.
- UI feedback (message-bar line, floating text). Rejected for v1 as noise; revisit if users ask.

## Risks

- **Balance:** topping off HP including mid-combat removes a deliberate tension the base game preserves. Mitigation: default-off, opt-in per user.
- **Hook ID collision:** picking any ID in the same band as upstream sfall's next hook would force a future renumber. Mitigation: this spec establishes the `100+` fallout2-ce-local range (see §"Why ID 100"), widening the existing `49..60` reservation comment to `49..99` so upstream sfall has runway. Our `HOOK_ONLEVELUP = 100` is collision-free against any reasonable upstream trajectory. If a collision does happen someday, renumbering is an engine-only churn — `.ssl` scripts reference hooks by name; the enum integer is engine-private.
