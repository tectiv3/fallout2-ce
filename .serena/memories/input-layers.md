# Input subsystem — the two keyboard states and three mouse modes

## Two parallel keyboard state stores

The engine tracks keys in **two** places and they don't talk to each other automatically:

1. **Engine's `gPressedPhysicalKeys[]`** (src/kb.cc) — updated by `_kb_simulate_key()` and by `_GNW95_process_key()` when SDL_KEYDOWN/UP events are polled in `src/input.cc:976`.
2. **SDL's own keyboard state** queried via `SDL_GetKeyboardState()` — updated only when SDL itself processes `SDL_KEYDOWN`/`SDL_KEYUP` events off its event queue.

`sfall_kb_is_key_pressed()` in `src/sfall_kb_helpers.cc:299` uses **SDL's state**, not the engine's. So FO2tweaks highlighting and any other sfall `key_pressed()` consumer won't see a key you only injected via `_kb_simulate_key`. To simulate a held modifier that both engine and sfall see, use `SDL_PushEvent(SDL_KEYDOWN)` / `SDL_PushEvent(SDL_KEYUP)` — the SDL event loop propagates it to both paths.

## Mouse modes — `mouseDeviceUsesRelativeMode()` vs `gUseTouchscreenMode`

Independent flags. Both matter.

- `mouseDeviceUsesRelativeMode()` (src/dinput.cc): cached from `screenIsFullscreen()` at `mouseDeviceInitMode`. Controls whether `_mouse_simulate_input(dx, dy, btn)` adds deltas to the cursor position (relative mode — "trackpad") or teleports the cursor to `(dx, dy)` (absolute mode). iOS + windowed=0 → relative.
- `gUseTouchscreenMode` (src/touch.cc): per-screen override set by `touch_set_touchscreen_mode()`. When true, the touch handler snaps the cursor to the finger position on every move via `_mouse_set_position(centroid.x, centroid.y)`. Enabled explicitly in inventory, skilldex, elevator, automap, main menu, load/save, options, preferences — and in `gameMouseSetMode(GAME_MOUSE_MODE_MOVE)` which is gameplay's default walk cursor.

The gameplay-MOVE case is what made the cursor teleport during combat on iPad. `src/game_mouse.cc` now guards that with `#if __APPLE__ && TARGET_OS_IOS` so gameplay stays in relative mode on iPad while UI screens keep their existing touchscreen-mode behavior.

## Absolute-position tap in relative mode

To tap a specific screen coordinate when the mouse is in relative mode, you cannot pass `(x, y, BUTTON)` to `_mouse_simulate_input` directly — it will *add* those to the current cursor position (delta semantics). Correct pattern:

```cpp
_mouse_set_position(x, y);                 // teleport absolute
_mouse_simulate_input(0, 0, BTN_DOWN);     // zero-delta click
```

This is used for HUD tap-through in `src/mouse.cc` — the tap handler detects when a finger lands inside `gInterfaceBarWindow`'s rect (via `windowGetRect`) and uses this pattern so small HUD buttons are directly tappable even though gameplay is in trackpad mode.

## Touch gesture recognizer reliability (src/touch.cc)

- `kTap`: requires all participating fingers to begin AND end within `TAP_MAXIMUM_DURATION = 75ms`. This is strict enough that 3+ finger taps are unreliable — users rarely coordinate landing/lifting that tightly. Prefer `kLongPress` for multi-finger triggers.
- `kLongPress`: fires after `LONG_PRESS_MINIMUM_DURATION = 500ms` of fingers staying mostly still (movement becomes `kPan` instead).
- `kPan`: continuous; state `kBegan` on first recognition, `kChanged` per frame while fingers are down, `kEnded` when finger count changes or all lift.

Multi-finger **vertical swipes** on iPad conflict with iPadOS multitasking gestures (4-5 finger swipe → home / app switcher). 3-finger swipes are fine, 4+ finger swipes don't reliably reach the app. Prefer long-press for 4-finger triggers.

## iPad touch gesture bindings

Implemented in `src/mouse.cc`:

- 1-finger tap → left click (at cursor in game area, at finger on HUD)
- 2-finger tap → right click
- 1-finger drag → cursor delta (trackpad)
- 2-finger drag → mouse wheel
- 3-finger swipe down (past 1/3 screen height) → KEY_ESCAPE
- 3-finger long-press → hold LSHIFT (via SDL_PushEvent; enables FO2tweaks highlighting)
- 4-finger long-press → KEY_F6 (quicksave)

All gestures `SDL_Log` on trigger for console diagnosis.
