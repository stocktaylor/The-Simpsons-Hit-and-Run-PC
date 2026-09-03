# Keyboard & Mouse Input

Goal: re-enable keyboard and mouse controls, which the original PC release
supports but this SDL port doesn't. Written up after a user asked whether
this could be turned back on.

**Status: Not started. Scoping/plan only.**

## It's not disabled - it was never ported

The instinct is "there must be a flag for this," but there isn't one to
flip. Keyboard/mouse support lives entirely in Windows-only DirectInput
code, and none of it is compiled into this SDL/Linux build:

- `libs/radcore/src/radcontroller/directinputcontroller.cpp` (~2,770 lines)
  - the only place in the tree that classifies devices as `"Keyboard"`/
  `"Mouse"` (e.g. lines 1052-1065, 1799-1806, 1978-1984) - is commented out
  of the build at `libs/radcore/CMakeLists.txt:4`.
- `code/input/usercontrollerWin32.cpp`/`.h` (~1,740 lines - mouse-look,
  sensitivity/invert, keyboard `radKey` bindings, see
  `usercontrollerWin32.h:201-291`) and `code/input/FEMouse.cpp` (menu
  cursor) are commented out at `code/CMakeLists.txt:107,121`.
- All three, plus `code/input/inputmanager.h:25-30`, are gated behind a
  `RAD_PC` define. This port's `CMakeLists.txt:85-89` defines
  `RAD_CONSOLE`/`RAD_WIN32`/`RAD_SDL` for every target, but never `RAD_PC`
  - so `inputmanager.h` falls through to `#include <input/usercontroller.h>`,
  the **console** controller path, instead.
- That fallthrough also switches which `eButtonMap` enum compiles
  (`code/input/inputmanager.h:46-90`): the gamepad-shaped one (`DPadUp`,
  `A`, `B`, `X`, `Y`, `LeftStickX/Y`, `RightStickX/Y`, ...) instead of the
  PC action-shaped one (`MoveUp`, `Attack`, `Jump`, `Accelerate`,
  `SteerLeft`, `CameraLookUp`, ...) that keyboard/mouse bindings actually
  target.
- The SDL controller backend that *is* compiled,
  `libs/radcore/src/radcontroller/sdlcontroller.cpp` (1,849 lines), only
  enumerates `SDL_GameController`/joystick devices. No
  `SDL_KEYDOWN`/`SDL_EVENT_KEY_*`, no `SDL_MOUSE*`, no binding structure -
  it doesn't know keyboard/mouse exist.
- Someone already flagged this exact tradeoff in a comment while porting
  `guiscreenpausesettings.cpp` (see local working-tree diff): `RAD_PC`
  "switches the whole input subsystem to a Windows-only DirectInput backend
  that isn't portable here."
- The pause-menu "Controller" remap screen (`MENU_ITEM_CONTROLLER` in
  `guiscreenpauseoptions.cpp`) is separately disabled for non-`RAD_PC`
  builds too, so there's currently no UI expecting a second input device
  either.

## The interface already expects this, though

`libs/radcore/inc/radcontroller.hpp:111`, documenting
`IRadControllerSystem::GetControllerAtLocation`:

```
// Ps2 : "Port0\Slot0"  --> "Port1\Slot3"
// XBox :"Port0\Slot0"  --> "Port3\Slot2"
// PC  : "Joystick0"    --> "Joystick[n]" | "Mouse0" | "Keyboard0"
```

Keyboard and mouse were always meant to show up as ordinary
`IRadController` devices, identified by location string, alongside
joysticks - not as some separate subsystem. That's the hook to build on.

And critically: the console `eButtonMap` that's *already compiled in*
already has the axis pairs a mouse/keyboard scheme needs -
`LeftStickX`/`LeftStickY` for movement, `RightStickX`/`RightStickY` for
camera - plus the face/shoulder buttons for everything else. Nothing about
gameplay logic requires the PC action-enum specifically; it's just what
`usercontrollerWin32.cpp` happens to emit.

## Two ways to get there

### Phase 1 (recommended first): keyboard+mouse as virtual controllers, mapped onto the existing console button scheme

Add a new `IRadController`/`IRadControllerInputPoint` implementation for
keyboard and mouse (new file(s) alongside `sdlcontroller.cpp`, e.g.
`sdlkeyboardmouse.cpp`), registered into the same `radControllerSystemSDL`
that already watches SDL events (`sdlcontroller.cpp:1789-1805`,
`radControllerInitialize`), exposed at locations `"Keyboard0"`/`"Mouse0"`
per the documented convention above.

Map directly onto the console `eButtonMap` that's already active:

- WASD -> `LeftStickX`/`LeftStickY` (full deflection while held - simple
  digital-to-analog, no acceleration curve needed to start)
- Mouse motion delta -> `RightStickX`/`RightStickY` (camera look)
- Keys -> `A`/`B`/`X`/`Y`/`LeftTrigger`/`RightTrigger`/`Start`/etc, chosen
  to match whatever the gamepad currently does for jump/attack/interact/
  pause (need to confirm exact current bindings before finalizing a
  keyboard layout)

This needs **zero** changes to the ~60 `RAD_PC`-gated files, no reviving
`usercontrollerWin32.cpp`/`FEMouse.cpp`, no PC action-enum. It's real,
playable keyboard+mouse control using the input pipeline that already
works today for gamepads. Mouse sensitivity can be a hardcoded constant
initially rather than needing settings UI.

### Phase 2 (optional, later): authentic PC input feel

If Phase 1's "keyboard as a virtual gamepad" feel isn't good enough (no
acceleration curve, no rebinding, mouse-look tuned by feel instead of
matching the original PC's DirectInput math):

- Revive the `RAD_PC` path: un-comment `directinputcontroller.cpp`'s
  successor and port `usercontrollerWin32.cpp`/`.h` + `FEMouse.cpp`/`.h`
  against SDL instead of DirectInput.
- Switch `eButtonMap` back to the PC action-shaped enum for this platform.
- Restore the "Controller" pause-menu remap screen
  (`guiscreenpauseoptions.cpp`, `MENU_ITEM_CONTROLLER`).
- Reference `directinputcontroller.cpp`'s actual sensitivity/acceleration
  curves so mouse-look matches the original release's feel, not a guess.

Multi-day-to-week effort. Only worth it if Phase 1 ships and the control
feel is the thing people complain about.

## Open questions / risks

- **Simultaneous keyboard+gamepad:** need to check how
  `radControllerSystemSDL`/`InputManager` assign controllers to players
  (`MAX_PLAYERS = 4`, `constants/maxplayers.h`) - does adding a synthetic
  "Keyboard0"/"Mouse0" controller risk being treated as a second player, or
  conflicting with a physically-connected gamepad, rather than cleanly
  coexisting as alternate input for player 1?
- **Keybinding scheme:** need to confirm current gamepad-to-action mapping
  (what `A`/`B`/`X`/`Y` etc. actually do in-game right now) before choosing
  keyboard keys that match player expectations.
- **Mouse-look feel:** a naive delta-to-axis mapping in Phase 1 will feel
  different from the original DirectInput mouse-look; may need basic
  sensitivity tuning even before Phase 2's full port.
