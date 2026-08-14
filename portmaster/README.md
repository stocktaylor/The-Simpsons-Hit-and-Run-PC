# PortMaster packaging

This directory holds the versioned, hand-maintained source for the [PortMaster](https://portmaster.games/) package: `port.json` and the launch script. `scripts/build-portmaster.sh` combines these with a freshly compiled binary into a ready-to-zip package at `build-portmaster-<compiler>-<release|debug>/package/`. Nothing is bundled - SRR2 uses the device's own system SDL2/libpng/OpenAL directly (see the launch script's comments for why an earlier version's attempt to bundle libpng/OpenAL actually broke startup on real hardware).

## Status

Confirmed working (renders, runs, and drives at a stable 30fps) on a real device: an Anbernic RG40XX running ROCKNIX. Controller mapping (steering/gas/brake/etc. via `SDL_GAMECONTROLLERCONFIG`) has been played through and feels fine on that hardware.

Two real bugs found via that testing have been fixed since:

- The window used to always open at a hardcoded 800x600 regardless of what `simpsons.ini` actually had saved, only getting resized down once the config loaded later in boot - on a device with no window manager, that resize-without-recenter left the window partly off-screen (black bars along the top/left, unplayable). `Win32Platform::InitializeWindow()` now peeks at `simpsons.ini`'s saved resolution directly (before the engine's own config/file-loading systems are even up) and opens the window at the right size from the start. This applies to every platform, not just PortMaster, since the bug wasn't PortMaster-specific.
- Holding Start+Select together now quits the game, matching the convention most other PortMaster ports follow - gated behind the new `SRR2_PORTMASTER` CMake option (`build-portmaster.sh` always passes `-DSRR2_PORTMASTER=ON`), so it has no effect on non-PortMaster builds.

Still open:

- **Confirm the pre-seeded `simpsons.ini` resolution is right generally, not just on that one device.** 640x480 fullscreen (the smallest resolution preset the engine supports - see the launch script's comments) matched the RG40XX's 640x480 display exactly, but hasn't been checked against other PortMaster devices with different native resolutions.
- **Add the game data.** The port intentionally doesn't bundle the PC release's copyrighted assets - see `port.json`'s `"inst"` field and the main `README.md`.

## Still needed for an actual PortMaster submission

Per [the packaging guide](https://portmaster.games/packaging.html), a real submission also needs, alongside `port.json` and the launch script:

- `screenshot.png` (4:3, at least 640x480)
- `gameinfo.xml`
- `licenses/` inside the packaged `simpsonshitandrun/` directory, with license text for FFmpeg (statically linked into the binary itself via `SRR2_FFMPEG_STATIC`), SDL2/libpng/OpenAL (dynamically linked against the device's own copies, not bundled, but still worth attributing), and this project's own license
- Community testing in the PortMaster Discord's `#testing-n-dev` channel
- A PR against [PortsMaster/PortMaster-New](https://github.com/PortsMaster/PortMaster-New), including `tools/prepare_repo.sh` and `python3 tools/build_release.py --do-check`

None of that is done yet.
