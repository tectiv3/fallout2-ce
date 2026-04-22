# Touchscreen Mode: Always-On by Default (iOS only)

## Problem

Touch screen mode (`gUseTouchscreenMode`) currently defaults to **off**. Every UI screen
that wants direct-tap behavior must explicitly opt in with `touch_set_touchscreen_mode(true)`
on entry and `false` on exit. This is fragile — any new screen that forgets to opt in silently
gets trackpad-only behavior, which is a bad UX on touch devices.

Currently **16 call sites** across 13 files manage this flag manually.

## Proposal

Invert the default on iOS: touchscreen mode is **always on**, disabled only in:
- **Gameplay** (in-game walking/combat) — precision cursor control via trackpad
- **Worldmap** — panning over a large map, needs trackpad semantics

All other contexts (main menu, inventory, dialog, pipboy, skilldex, elevator, automap,
character editor, options, preferences, load/save) get touchscreen mode automatically.

## Key Design Decisions

### 1. "Main screen" = Gameplay, not Main Menu

The main menu is a simple button screen — direct tap is ideal. "Main screen" in the
user's request refers to the **gameplay screen** (walking around, combat), where trackpad
precision matters.

### 2. Platform scope: iOS only

The default `gUseTouchscreenMode = true` is guarded by `#if __APPLE__ && TARGET_OS_IOS`.
Other platforms keep `false` as default. The iOS guard in `gameMouseSetMode()` is preserved.
The push/pop infrastructure works on all platforms but the behavior change only affects iOS.

### 3. Combat stays in trackpad mode

Combat is gameplay — `gameMouseSetMode()` fires during combat transitions (crosshair mode,
move mode) and will continue to set `false`. No special combat handling needed.

## Architecture Challenge: The Restore Problem

The main tension in this design: **`gameMouseSetMode()` only fires on mode *changes***
(early return if `mode == gGameMouseMode`). When a UI screen opens from gameplay and closes
back to gameplay, `gameMouseSetMode` does NOT re-fire because the mode hasn't changed.

This means UI screens launched from gameplay **cannot simply rely on gameplay to reassert
`false`** — they must actively restore the correct state on exit.

### Recommended approach: Save/Restore pattern

Add a save/restore mechanism to `touch.cc`:

```cpp
static bool gSavedTouchscreenMode = true;

void touch_save_and_set_touchscreen_mode(bool value) {
    gSavedTouchscreenMode = gUseTouchscreenMode;
    gUseTouchscreenMode = value;
}

void touch_restore_touchscreen_mode() {
    gUseTouchscreenMode = gSavedTouchscreenMode;
}
```

This way:
- Gameplay sets `false` via `gameMouseSetMode` (keeps using `touch_set_touchscreen_mode`)
- UI screens use `touch_save_and_set_touchscreen_mode(true)` on entry and
  `touch_restore_touchscreen_mode()` on exit
- If opened from gameplay (false), they restore to false
- If opened from main menu (true), they restore to true
- New screens that don't call either function get the default: **true**

### Alternative: Simple approach (keep explicit pairs)

If save/restore is too much machinery, we can:
1. Change default to `true`
2. Remove iOS guard in `gameMouseSetMode` (always `false`)
3. Keep all `touch_set_touchscreen_mode(true)` on UI screen entry (still needed from gameplay)
4. Change all UI screen exits from `false` → `true` (since default is now true)
5. Gameplay reasserts `false` via `gameMouseSetMode` when mode changes occur

The risk: if a UI screen is opened from worldmap or another `false` context, exiting it
would incorrectly leave touchscreen mode `true`. The save/restore pattern avoids this.

## Files to Change

| File | Current Calls | Proposed Change |
|------|--------------|-----------------|
| `src/touch.cc` | `gUseTouchscreenMode = false` (default) | Change default to `true`, add save/restore helpers |
| `src/touch.h` | declares `touch_set_touchscreen_mode` | Add `touch_save_and_set_touchscreen_mode`, `touch_restore_touchscreen_mode` |
| `src/game_mouse.cc` | `#if iOS: false; #else: mode==MOVE` | Always `false` (remove #if guard) |
| `src/worldmap.cc` | `false` on entry only | Keep `false` on entry |
| `src/inventory.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/elevator.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/pipboy.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/game_dialog.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/automap.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/skilldex.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/character_editor.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/options.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/preferences.cc` | `true` on entry, `false` on exit | Use save/restore |
| `src/loadsave.cc` | Conditional logic | Use save/restore (always save, set true, restore on exit) |
| `src/mainmenu.cc` | `true` on unhide, `false` on hide | Remove both (default true handles it) |

## Open Questions for Review

1. **Should worldmap also use save/restore?** Currently only sets `false` on entry with no
   restore. Worldmap always exits to a map load → gameplay, so `false` on exit is correct.
   Probably fine as-is.

2. **Loadsave conditional logic** — currently only enables touchscreen for non-quick modes.
   With always-on default, should quicksave also get touchscreen? (Quicksave has minimal UI
   so probably doesn't matter either way.)

3. **Is a stack needed instead of single save slot?** If screens can nest (e.g., gameplay →
   inventory → some sub-dialog), a stack would be safer. Current nesting depth is shallow
   (at most 2 levels), so a single save slot likely suffices, but a small stack would be
   more robust.
