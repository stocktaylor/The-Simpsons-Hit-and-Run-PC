# Controller Button Icons

Goal: show button-prompt icons that match whatever controller is actually
plugged in (Xbox/PlayStation/Switch-style face buttons), inspired by the
`ControllerButtonIcons` Lucas Mod Loader mod, but implemented natively in
our source rather than depending on that mod or its assets.

**Status: Parked. Phase 1 implementation was rolled back** after testing
against real game data revealed the core assumption it was built on doesn't
hold - see "Why Phase 1 was rolled back" near the bottom before picking
this back up.

## What the mod actually does (and why we can't just reuse it)

Decompiled its `.lmlm` package (plain-text metadata is readable inside the
binary archive). It's not a game-engine feature - it's an external, Windows-
only DLL-injection mod loader. On load of `frontend.p3d`/`ingame.p3d`, a Lua
`[PathHandlers]` script redirects to one of several **complete alternate
copies** of the whole frontend/ingame Scrooby UI package, chosen by a user
setting:

```
if GetSetting("Style") == 2 then Redirect("/GameData/frontendXbox.p3d")
if GetSetting("Style") == 3 then Redirect("/GameData/frontendPS2.p3d")
if GetSetting("Style") == 4 then Redirect("/GameData/frontendGCN.p3d")
...
```

Each redirect target is a full UI package re-authored by the modder
("Colou", per the credit in the metadata) with different button glyph
textures baked into every relevant sprite. Two variants are explicitly
labelled "(Custom)" (Xbox 360, Wii U/Switch) since SRR2 never shipped on
those platforms - confirming they're fan-made, not extracted from a real
release.

This can't be ported directly:
- The injection mechanism is Windows-DLL-based; there's no equivalent on
  our native Linux/SDL build.
- The alternate `.p3d` packages are binary art assets we don't have and
  can't rebuild (no Scrooby export tooling in this repo).

## What already exists in our C++ source (narrower than it sounds)

- `code/presentation/gui/frontend/guiscreencontroller.cpp` picks between
  Scrooby pages `ControllerGC`/`ControllerPS2`/`ControllerXBOX` (the "how to
  hold your controller" diagram screen only) via `#ifdef RAD_GAMECUBE`/
  `RAD_PS2`/else - a **compile-time**, one-screen-only mechanism.
- `code/presentation/gui/guiscreen.h`/`.cpp` has a generic `eButtonIcon`
  with exactly two values, `BUTTON_ICON_ACCEPT` and `BUTTON_ICON_BACK`
  (`guiscreen.cpp:212-270`). Nearly every menu screen has an `AcceptLabel`/
  `BackLabel` group, and on `RAD_WIN32` (our build) these show a **sprite**
  icon (vs. outlined text on console builds). `SetButtonVisible()`/
  `IsButtonVisible()` only show/hide it - there's no code path that changes
  *which* graphic is shown.
- Checked `FeSprite.cpp`'s `FE_CHAR_MAP` (looked like it might be an inline
  icon-in-text mechanism) - it's just standard bitmap-font glyph mapping,
  not usable for icon substitution. Ruled out.

So Accept/Back is the one place with an existing, reusable per-screen hook.
Every other individual button prompt (shoulder buttons, face buttons in
tutorials/minigames, etc.) is just a hardcoded sprite on whichever screen
needs it, with no shared abstraction - matching one of those would mean
finding and touching that screen's code individually.

## Technical path that looks buildable

Two pieces confirmed present and reusable:

- **Runtime controller-type detection**: gamepad input already goes through
  SDL (`libs/radcore/src/radcontroller/sdlcontroller.cpp`, established
  during the PortMaster research). SDL can report controller type (Xbox/
  PlayStation/Switch/generic) via `SDL_GameControllerType`/
  `SDL_GetGamepadType` depending on SDL2 vs SDL3. This part is decoupled
  from the UI work and could be built and tested standalone first.
- **Runtime texture swap without touching original assets**: `Scrooby::
  Sprite` (`libs/scrooby/inc/Sprite.h`) exposes `SetRawSprite(tSprite*,
  bool updateDrawable)` and `SetImage(int index, const char* alias)`. And
  `libs/pure3d/p3d/png.cpp` (`tPNGHandler::CreateImage`) already has a full
  PNG-to-texture loading path used elsewhere in the engine. So loading a
  handful of loose PNG icon files at startup and binding them onto the
  existing Accept/Back sprite objects at runtime looks architecturally
  sound, without needing to touch or rebuild any `.p3d` asset.

## Proposed phasing

**Phase 1 (realistic first deliverable): Accept/Back only.**
1. SDL controller-type detection, exposed as a simple query (e.g. on
   `Win32Platform` or a small new helper), independent of any UI code.
2. Source or create a small icon set (Xbox/PlayStation/Switch/generic style
   "A/Cross" and "B/Circle" glyphs) - licensing needs to be resolved, see
   below.
3. Load those as textures via the existing PNG path at startup.
4. In `CGuiScreen`'s Accept/Back setup (`guiscreen.cpp:212-270`), swap the
   sprite's image based on detected controller type instead of just
   toggling visibility.
5. Test across screens that show Accept/Back (this is most menus, so it's
   good coverage for a first pass despite being "only" two icons).

**Phase 2 (larger, not scoped in detail yet): broader per-prompt coverage.**
Cataloguing every individual hardcoded button-prompt sprite across
tutorials/minigames/HUD and giving each the same runtime-swap treatment.
This is materially more work - it means finding every such sprite
individually (no shared list exists in code) and would need its own pass
once Phase 1 proves the mechanism out.

## Why Phase 1 was rolled back

Phase 1 was implemented (new `code/presentation/gui/controllericons.h`/
`.cpp`, an `assets/button_prompts/` asset subset, and a hook into
`guiscreen.cpp`'s existing `RAD_WIN32` Accept/Back sprite setup at
`guiscreen.cpp:212-270`) on the assumption that `GetSprite("Accept")`/
`GetSprite("Back")` on the `AcceptLabel`/`BackLabel` groups would return an
existing baked-in icon sprite we could swap via `Scrooby::Sprite::
SetRawSprite()`.

Tested against real game data (with diagnostic logging added to confirm),
that assumption is wrong: on every screen tested, `AcceptLabel` contains
1-2 `Text` children and `BackLabel` contains 2 `Text` children - never a
`Sprite`. There is no pre-existing icon sprite to swap; the prompt renders
as plain text (matching what the non-`RAD_WIN32` console branch already
does via `GetText("Accept")`). This is almost certainly why the
`ControllerButtonIcons` mod exists in the first place and why it replaces
the *entire* frontend/ingame UI package rather than reskinning one sprite -
the icon rendering it adds isn't present in the base game data at all.

Given that, "swap a sprite" isn't the right shape for this feature. The
real fix would be inserting a *new* drawable into the group where only text
exists today, which means figuring out whether Scrooby's underlying
`FeGroup`/`FeParent` implementation supports runtime child insertion (there
is a plausible path - `FeParent::AddChild` is used internally elsewhere,
e.g. `FeText::AddHardCodedString` in `libs/scrooby/src/FeText.cpp` - but
this was never verified for inserting a new `Sprite`-type child into a
`Group`). That's materially more investigation than Phase 1's original
scope, so implementation was rolled back rather than pushed further
speculatively.

**All Phase 1 code was reverted**: `controllericons.h`/`.cpp`,
`assets/button_prompts/`, and the `guiscreen.cpp`/`code/CMakeLists.txt`
hook-ins are all removed/reverted as of this rollback. Nothing from Phase 1
remains in the tree.

## If this gets picked back up

- Check whether `Scrooby::Group`'s concrete implementation
  (`libs/scrooby/src/FeGroup.*` or wherever it lives) exposes or can be
  extended to support adding a new child `Sprite` drawable at runtime,
  positioned to sit where the `Text` child currently renders. This is the
  actual blocker, and needs answering before any other work here is worth
  doing.
- If runtime insertion turns out not to be viable, a fallback worth
  considering: overlay a custom-drawn icon via pddi's own sprite/texture
  drawing directly (bypassing Scrooby's scene graph entirely for this one
  element), positioned using the existing `Text` child's bounding
  box/position as a reference point.
- The curated CC0 icon subset (Xbox/PlayStation/Switch/Steam Deck/keyboard,
  Accept+Back) and the SDL controller-type detection logic
  (`SteamDeck` env var, then `SDL_GameControllerType`/`SDL_GamepadType`)
  are still sound and can be reused as-is once the rendering approach is
  figured out - it was only the "swap an existing sprite" mechanism that
  didn't hold up, not the asset curation or detection logic.
- Broader per-prompt coverage (every other hardcoded button-prompt sprite
  in tutorials/minigames/HUD, beyond Accept/Back) is still out of scope and
  would need its own pass regardless of how Accept/Back ends up working.
