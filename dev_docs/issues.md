# Known Issues

## Nearby traffic cars occasionally despawn

Traffic vehicles sometimes disappear even when close to the player, not just
when far away/out of view as intended.

**Status:** Not yet root-caused. Occurs less frequently since the frame rate
cap / forced vsync changes were added, but still happens.

**What's been ruled out:**
- Not a frame-count-based timer bug. `TrafficManager`'s visibility-based
  removal (`code/worldsim/traffic/trafficmanager.cpp`, around lines 934-943)
  accumulates real elapsed milliseconds (`mMillisecondsOutOfSight += milliseconds`)
  and resets to 0 the instant a car re-enters the camera frustum, so it's
  already framerate-independent by construction.

**Where to look next:**
- `GameplayManager::TestPosInFrustrumOfPlayer` (`code/mission/gameplaymanager.cpp:352`)
  does the actual frustum test via `SphereVisible` against the camera's live
  FOV/aspect. Worth checking whether this can transiently return false for a
  car that's actually still on-screen (e.g. camera update ordering/staleness,
  or aspect-ratio mismatch between this test's camera and the render camera).
- Note: there's a `SetFarPlane(250.0f)` hack in that function for non-SuperSprint
  gameplay, but that only affects cars farther than 250m away, so it doesn't
  explain despawns of *nearby* cars.
- `MAX_MILLISECONDS_OUT_OF_SIGHT_BEFORE_REMOVAL` in `trafficmanager.cpp`
  controls how long a car can be judged "out of sight" before it's removed -
  worth checking if it's short enough that even brief, transient frustum-test
  flicker could trigger a removal.

## Loading speed still tied to presentation rate under compositors like gamescope

**Priority:** Low, not being worked on right now.

Loading throughput is coupled to how often the main loop iterates, not just
to our own vsync setting. The async file loader (`radLoadManager` in
`libs/radcontent/src/radload/manager.cpp`) runs on a real background thread,
but it's gated by a mutex handoff with the main thread - the background
thread starts blocked waiting to acquire the mutex, which is only released
when the main loop calls `p3d::loadManager->SwitchTask()` (in
`code/main/game.cpp`). That call happens exactly once per loop iteration,
back-to-back with `RenderManager::ContextUpdate()`'s `SwapBuffers()`. So
however often the loop iterates - which is bounded by how fast
`SwapBuffers()` returns - directly caps how often the loader gets scheduled.

This session already fixed our own code's contribution to that (the frame
rate cap and forced-vsync settings both now exempt loading, see
`RenderManager.cpp` and `game.cpp`). But on a device like the Steam Deck,
the compositor (gamescope) sits between the game and the display and can
enforce its own vsync/frame pacing independent of what the app requests via
`SDL_GL_SetSwapInterval` - so `SwapBuffers()` (and therefore every loop
iteration, and therefore every loader handoff) can still end up capped at
the display's refresh rate regardless of our own vsync flag.

**What the real fix would look like:** stop tying the loader pump 1:1 to
render/present cadence during loading. Instead of calling `SwitchTask()`
once per loop iteration, spin it in a tight loop (or for a small time
budget, e.g. a few ms) between renders while a load is in progress, and only
render/present a loading-screen frame occasionally (e.g. every N pumps or
every X ms) rather than every single pump. That way even if presentation
itself is capped at 60Hz by a compositor, the loader still gets scheduled
far more than 60 times/sec in between renders. This would touch the main
loop in `code/main/game.cpp` and/or the loading context's update loop.

## Pause menu Controller screen is empty

The pause menu's "Controller" screen (`code/presentation/gui/frontend/
guiscreencontroller.cpp`) was re-enabled - it was previously disabled via
`#ifndef RAD_PC` as a "[TEMP] ... free up some memory" hack from the
original developers, which ends up applying to this build since `RAD_PC`
is never defined here. Re-enabling it crashed on construction (confirmed
via gdb backtrace): it does several `Scrooby Page` lookups by name
(`"ControllerPC"`, `"ControllerImage"`, then `"ControllerXBOX"` since this
build defines `RAD_CONSOLE` without `RAD_GAMECUBE`/`RAD_PS2`), each guarded
by an `rAssert` but then unconditionally dereferenced on the next line.
Since asserts here log and continue rather than halt, a missing page fell
straight into a null-pointer crash.

**Status:** Crash fixed (proper NULL checks + graceful early-out added if
a required page/group is missing), but the screen itself now just renders
empty - `"ControllerImage"` genuinely doesn't exist in this asset set, so
there's no controller diagram/button-legend art to show. Not investigated
further; low priority since it doesn't crash anymore.

**Where to look next:** confirm exactly which of the four page lookups in
the constructor (`"ControllerPC"`, `"ControllerImage"`, `"ControllerXBOX"`,
`"TextLabels"` group within it) are actually missing vs. present - only
`"ControllerImage"` was confirmed missing before the fix (that's what the
original crash hit first; the fix means later lookups now silently return
early without confirming which of them would also be missing). If none of
the platform-specific diagram art exists on PC, this may need entirely new
art (or reusing one of the console pages' art, e.g. `"ControllerXBOX"`,
if that one does turn out to be present) rather than a code fix.
