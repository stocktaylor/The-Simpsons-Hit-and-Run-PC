# D'oh!

This is a port of The Simpsons Hit & Run to the Nintendo Switch and PS Vita based on the leaked source code. The full game should be playable, including local multiplayer in the bonus game. The port is however still incomplete, so some glitches can be observed and some visual effects are missing compared to the PC version.

Please report any bugs or feature requests in the issues tab on this Github repository.

# Installation

This port uses the PC assets, so you will need to have the PC version of the game installed. Do not use the assets from the source code leak as those are not the final version, instead use the assets from the official release. Also make sure you're using the original `.rmv` movie files in the `movies` folder rather than the converted `.bk2` files that older releases of the port required.

To install the port simply copy the contents of the installation folder to `sdmc:/switch/simpsons` on the Switch or `ux0:/data/simpsons` on the Vita.

Finally download the [latest release](https://github.com/ZenoArrows/The-Simpsons-Hit-and-Run/releases) of this port and copy it to your console. On the Switch you simply put the `.nro` file into the same folder as the game data (`sdmc:/switch/simpsons`), on the Vita you can copy the `.vpk` file anywhere and install it using [VitaShell](https://github.com/TheOfficialFloW/VitaShell).

On the PS Vita this game also requires that you have `libshacccg.suprx` installed on your console. This will be installed during the first run setup of the [VitaDB Downloader](https://vitadb.rinnegatamante.it/#/info/877), but can also be installed separately using [ShaRKBR33D](https://vitadb.rinnegatamante.it/#/info/997).

# Multi-Language support

The PAL version supports multiple languages and will use the language that matches the system language of your console. If your console is set to a language that is not supported a menu will be shown giving you the option to choose between the supported languages.

No official release has the dialog RCF files for all 4 supported languages, so you will need to make sure you use the game assets from a release that's localized in the language you'd like to play.

If you'd just like to play in English and have no need for multi-language support, then use the NTSC version to play.

# Building from source

This project primarily targets the Nintendo Switch and PS Vita, but the CMake build also supports building a native desktop binary for Linux and Windows, which is useful for development and testing.

## Desktop (Linux and Windows)

All desktop builds are done via the scripts in `scripts/`, each building inside a pinned container (via `docker` or `podman`) rather than against whatever toolchain/library versions happen to be installed on your machine. This is deliberate: building natively against an arbitrary host toolchain adds variables that make "it doesn't build for me" hard to reproduce, and for the Linux build specifically, a host with a newer glibc than the container's baseline (e.g. current Fedora) silently produces a binary that won't run on other Linux systems (see `scripts/build-linux-x86.sh` for why). Building through these scripts keeps everyone's builds - and any bug reports about them - on the same footing.

Install Docker or Podman first; set `CONTAINER_RUNTIME=podman` in your environment if you're using Podman instead of Docker.

Every script accepts:

- `--debug` - build a Debug build instead of the default Release.
- `--gcc` - compile with GCC instead of the default Clang. Not available on `build-windows-arm.sh`, which has no GCC-based cross compiler for that target and will error out if you pass it, rather than silently building with Clang anyway. `build-linux-arm.sh` and `build-portmaster.sh` invert this: GCC is their default and `--clang` opts into Clang instead, since Clang's cross-compile toolchain detection currently doesn't work for that target (see those scripts' comments).

Flags can be combined in any order, e.g. `./scripts/build-linux-x86.sh --gcc --debug`.

### Linux x86_64

```
./scripts/build-linux-x86.sh
```

Builds inside Valve's official Sniper SDK container (the same Debian 11-based baseline the Steam Runtime uses, including on the Steam Deck), statically linking FFmpeg so the result has no system FFmpeg dependency and runs on other modern x86_64 Linux systems as-is. Produces `build-linux-x86-<compiler>-<release|debug>[-gles2]/code/SRR2`.

Pass `--gles2` to build the GLES2 PDDI backend (`libs/pure3d/pddi/gles`) instead of the default desktop OpenGL one - useful for testing that backend without the cross-architecture container overhead of the ARM/PortMaster builds below.

### Linux ARM64

```
./scripts/build-linux-arm.sh
```

Cross-compiles for aarch64 Linux from an x86_64 host using Debian's multiarch cross toolchain (`crossbuild-essential-arm64`) inside an ordinary x86_64 Debian 11 container - there's no Valve Sniper SDK image for arm64 yet (checked directly; every published tag is amd64-only), so this uses plain Debian 11 instead, and cross-compiles rather than running a QEMU-emulated arm64 container so the build needs nothing beyond docker/podman on the host (see the script's comments for why the QEMU route was dropped). This is a first attempt at this target, so expect it to need iteration. Also accepts `--gles2`. Produces `build-linux-arm-<compiler>-<release|debug>[-gles2]/code/SRR2`.

### PortMaster

```
./scripts/build-portmaster.sh
```

Builds for [PortMaster](https://portmaster.games/), the handheld-emulation-device porting platform. Same cross-compile approach as the ARM64 build above, always using the GLES2 PDDI backend, since PortMaster's target devices have no full desktop OpenGL. Produces `build-portmaster-<compiler>-<release|debug>/code/SRR2`, and stages a full PortMaster package at `build-portmaster-<compiler>-<release|debug>/package/` using the versioned `port.json`/launch script in `portmaster/` - see that directory's [README](portmaster/README.md) for what's still needed to finish and submit a port (game data, screenshot, gameinfo.xml, PR submission). This is a first attempt at this target, so expect it to need iteration. `SRR2` reads real SDL gamepad input for gameplay (confirmed via `libs/radcore/src/radcontroller/sdlcontroller.cpp`), so the launch script relies on PortMaster's `SDL_GAMECONTROLLERCONFIG` rather than `gptokeyb`.

### Windows x86_64

```
./scripts/build-windows-x86.sh
```

Cross-compiles from Linux inside a Fedora container. Produces `build-windows-x86-<compiler>-<release|debug>/code/SRR2.exe`.

### Windows ARM64

```
./scripts/build-windows-arm.sh
```

Cross-compiles from Linux inside a Fedora container, using a downloaded llvm-mingw toolchain since Fedora has no GCC-based mingw cross compiler for this target. This is a first attempt at this target, so expect it to need iteration. Produces `build-windows-arm-clang-<release|debug>/code/SRR2.exe`.

### Running

As with the console ports, this build uses the PC release's assets rather than the leaked source code's assets. Copy the contents of the PC installation folder (`art`, `movies`, etc., using the original `.rmv` movie files) alongside the `SRR2` binary, then run it from that directory.
