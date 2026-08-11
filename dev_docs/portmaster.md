# PortMaster Viability Research

Research-only. No source changes were made for this. Goal: figure out how
plausible it is to eventually ship this as a PortMaster port for ARM
handhelds, and what would actually need to happen to get there.

Source: https://portmaster.games/porting.html, https://portmaster.games/packaging.html,
https://portmaster.games/build-environments.html (fetched 2026-08-09).

## What PortMaster actually requires

- **Target hardware:** ARM handhelds (Anbernic and similar), aarch64 and
  32-bit ARM, mostly Rockchip SoCs on old 3.x Linux kernels with proprietary
  Mali drivers.
- **OS:** Linux-based CFWs - AmberELEC, uOS, ArkOS, muOS, Knulli, Rocknix.
  PortMaster ships its own dependencies rather than relying on the CFW's.
- **Graphics:** No desktop OpenGL, no X11/Weston. Only **OpenGL ES 2.0**
  natively, or **OpenGL up to 2.x via GL4ES** as a translation layer. Output
  is KMS/DRM or SDL2 - no Vulkan, no display manager. NPOT textures are
  limited (only `GL_CLAMP` reliable unless the GLES hardware supports NPOT
  natively), and multiple color framebuffer attachments aren't supported.
- **Accepted port categories** (5 total) - the relevant one for us is
  *"custom open-source engines using original game assets"* (this is
  exactly what this repo already is).
- **Input:** `gptokeyb` maps keyboard/mouse/joystick via a control file;
  standard quit combo is start+select.
- **Packaging layout:**
  ```
  portname/
    port.json
    README.md
    screenshot.jpg  (gameplay, 4:3, min 640x480)
    gameinfo.xml
    cover.jpg (optional)
    Port Name.sh
    portname/
      licenses/LICENSE files
      <port files>
  ```
  Port name: lowercase letters/digits/`.`/`_`, must be unique project-wide.
  Launch script keeps capitalized display name, must end `.sh`.
- **Build environment:** Docker cross-compile is the preferred path
  (portmaster.games/docker.html). The documented WSL2 fallback is Ubuntu
  22.04 + `gcc-aarch64-linux-gnu`/`g++-aarch64-linux-gnu` + `qemu-user-static`,
  building against a pinned **SDL2 2.26.2** (built from source and
  `apt-mark hold`'d so nothing overwrites it), plus `libdrm-dev`,
  `libopenal-dev`, `libsdl2-mixer-dev`, `libfreetype6-dev`, `libcurl4`,
  `libgbm-dev`, cmake, ninja-build, premake4, autoconf.
- **Testing:** must run on all major CFWs at 640x480, 720x720, and 1280x720.

## How this codebase already lines up

This is a better starting position than a typical "get an x86 engine
running on ARM" port, for a few concrete reasons found in-tree:

- **A GLES2 desktop/SDL backend already exists and isn't Vita-only.**
  `libs/pure3d/CMakeLists.txt` wires `-DSRR2_P3D_PDDI=GLES2` (independent of
  `VITA`/`SRR2_USE_VITAGL`) to compile
  `pddi/gles/display_win32/gldisplay.cpp` - an SDL-based GLES2 context, not
  the desktop GL path this session has been building against. That's
  exactly the rendering path PortMaster requires (no desktop GL, no X11).
  It hasn't been exercised on this Linux build yet (we've only been
  building/testing the `GL`/desktop path), so treat it as "present but
  unverified," not "working."
- **Gamepad input is already SDL-backed**, via
  `libs/radcore/src/radcontroller/sdlcontroller.cpp`. The Windows-only
  DirectInput path (`code/input/usercontrollerWin32.cpp`) exists in the tree
  but isn't the one this build compiles against (see the `RAD_PC` notes in
  `dev_docs/issues.md`'s sibling context / prior session history - this
  build never defines `RAD_PC`). This means controller support has a real
  shot at mapping onto `gptokeyb` without an input-layer rewrite, but it
  hasn't specifically been tested with a physical gamepad in this session -
  worth verifying before assuming it's a non-issue.
- **No meaningful x86-specific code.** A repo-wide search for x86
  intrinsics/inline asm (`__asm`, `_mm_*`, `xmmintrin`/`emmintrin`,
  `intrin.h`) only turns up hits in `libs/pure3d/pddi/dx8/` (Windows/DX8
  only, not compiled here), `libs/radscript/.../win32/` (Windows-only), and
  one optional path in `libs/radcore/src/radmemory/dlheap.cpp`. Nothing in
  the actual game/render/physics code blocks an ARM build architecturally.
- **A config-file system already exists** (`GameConfigManager`, this
  session's recent work) that could carry PortMaster-specific defaults
  (e.g. GLES2 PDDI, a conservative frame rate cap) without touching the
  original `simpsons.ini` format used by the PC build.
- **The existing frame rate cap / forced vsync work in this session is
  directly relevant here** - these are exactly the kind of underpowered,
  fixed-hardware ARM devices where pacing the sim to a known dt (30/60fps)
  instead of "whatever the display allows" matters even more than it does
  on a 360Hz desktop monitor.

## Real gaps / unknowns

- **FFmpeg on ARM.** The Linux build here links system `libavformat`/
  `libavcodec`/`libavutil`/`libswresample`/`libswscale` via pkg-config.
  PortMaster targets don't have these system-wide; they'd need to be cross-
  compiled for aarch64 and bundled in the port's `libs/` folder (this is a
  normal, accepted pattern for other ports, just extra build work). Worth
  checking early whether the specific FFmpeg feature set used here
  (mainly video/audio demuxing+decoding for FMV playback, per
  `libs/radmovie/src/common/ffmpegmovieplayer.cpp`) is light enough to trim
  down, since a full modern FFmpeg build is large for a storage-constrained
  handheld port.
- **GLES2 path is untested on this Linux build.** Everything this session
  has verified compiling/running is the desktop-GL (`SRR2_P3D_PDDI=OpenGL`)
  path. Before assuming PortMaster viability, it's worth doing a local
  `-DSRR2_P3D_PDDI=GLES2` build (still on the desktop, via Mesa's GLES2
  support) as a cheap way to shake out GLES-specific bugs before ever
  touching real ARM hardware or a cross-compiler.
  - NPOT texture handling in particular deserves a look, given PortMaster's
    explicit warning about `GL_CLAMP`-only NPOT support on some of this
    hardware.
- **Performance is a real open question, not just a formality.** This is a
  PS2/Xbox-era open-world game (traffic, pedestrians, physics sim - see
  `code/worldsim/`), and PortMaster's target devices are considerably
  weaker than a modern desktop GPU, running through GL4ES translation in
  some cases. No profiling against anything ARM-class has been done. This
  is the single biggest risk to "is this actually playable," separate from
  "does it compile and run at all."
- **No cross-compile toolchain has been set up or tried.** Everything so
  far is native x86_64 Linux. Getting an aarch64 toolchain (Docker method
  per PortMaster's own guide) building this CMake project has not been
  attempted.
- **Packaging/input-mapping work is all upfront, not started.** `port.json`,
  `gameinfo.xml`, the launch script, and a `gptokeyb` control file all need
  to be authored from scratch - none of this exists yet.
- **Asset licensing/distribution.** Like other PortMaster ports for
  commercial games, this would need a "bring your own game files" flow
  (the port script checking for/prompting for the original PC retail
  assets), not bundling copyrighted assets. That's an accepted, common
  pattern on PortMaster, not a blocker, but it needs to be built into the
  launch script and documented in the port's `README.md`.

## Suggested order of investigation (not started)

1. Local `-DSRR2_P3D_PDDI=GLES2` desktop build (via Mesa), fix whatever
   breaks. Cheapest possible signal on whether the GLES2 path is real.
2. Confirm gamepad input actually works via `sdlcontroller.cpp` on this
   Linux build with a physical controller (currently unverified either way).
3. Look at trimming the FFmpeg feature set / confirm aarch64 cross-compile
   is realistic for the exact codecs FMV playback needs.
4. Only after 1-3 look reasonable: attempt an actual aarch64 cross-compile
   (Docker method) and get a binary that at least launches under QEMU or on
   real hardware, before investing in packaging/`port.json`/`gptokeyb`
   mapping/submission.

## Bottom line

Nothing found here rules it out. The engine already has more of what
PortMaster wants (GLES2 backend, SDL-based input, no x86 lock-in) than a
typical native-Windows-engine port would, which is a genuinely good sign.
The two things that actually determine whether this is worth pursuing -
real ARM/GLES2 rendering correctness and real-world performance on
PortMaster-class hardware - are both unverified and would need to be
answered before any packaging work is worth doing.
