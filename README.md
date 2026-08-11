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

This project primarily targets the Nintendo Switch and PS Vita, but the CMake build also supports building a native desktop binary, which is useful for development and testing. This has been verified to build and link successfully on Linux.

## Linux

### Dependencies

Install the following development packages. On Debian/Ubuntu:

```
sudo apt install build-essential cmake pkg-config libsdl2-dev libpng-dev \
	libopenal-dev libavformat-dev libavcodec-dev libavutil-dev \
	libswresample-dev libswscale-dev
```

On Arch Linux:

```
sudo pacman -S base-devel cmake pkgconf sdl2 libpng openal ffmpeg
```

On Fedora (or Fedora-derived distros):

Fedora's official repos don't include `ffmpeg-devel` (patent restrictions). Either enable [RPM Fusion](https://rpmfusion.org/Configuration) `free` first:

```
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install gcc-c++ cmake pkgconf-pkg-config SDL2-devel libpng-devel openal-soft-devel ffmpeg-devel
```

or stay on official repos only by using `ffmpeg-free-devel` in place of `ffmpeg-devel`:

```
sudo dnf install gcc-c++ cmake pkgconf-pkg-config SDL2-devel libpng-devel openal-soft-devel ffmpeg-free-devel
```

The build system will use SDL3 if it's found, otherwise it falls back to SDL2. As of this writing the SDL3 packages in most distro repos are too new for the SDL3 API calls used in this codebase (they've renamed/removed some functions this project still uses), which causes build errors. SDL2 is the safer choice for now; to force it even if SDL3 is installed, pass `-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON` to the `cmake` configure command below.

### Build

From the repository root:

```
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

This produces the `SRR2` executable at `build/code/SRR2`.

By default this also builds a few sample programs for internal libraries (`SRR2_BUILD_TESTS=ON`). On GCC/Linux, the `simplemovie` sample currently fails to link with an `undefined reference to vtable for radWatcherEnabledProfiler` error — this is a pre-existing bug unrelated to these instructions (the class's virtual methods are defined behind a permanently-disabled `DEBUGWATCH` macro, which MSVC tolerates but GCC's ABI doesn't) and does not affect the `SRR2` target itself. If you'd like a clean build without it, pass `-DSRR2_BUILD_TESTS=OFF` to the `cmake` configure command:

```
cmake -B build -DCMAKE_BUILD_TYPE=Release -DSRR2_BUILD_TESTS=OFF
cmake --build build -j$(nproc)
```

### Portable builds (no system FFmpeg dependency)

By default the Linux build links against your distro's FFmpeg via pkg-config, which ties the resulting binary to that exact FFmpeg version. It'll run fine on the machine that built it, but copying it to another machine (e.g. a Steam Deck) can fail with a missing `libavformat.so`/`libavcodec.so`/etc. if that machine ships a different FFmpeg build - and on an immutable OS like SteamOS you can't just install a matching one.

Pass `-DSRR2_FFMPEG_STATIC=ON` to build and statically link a minimal FFmpeg instead (source fetched automatically via CMake's `ExternalProject`, so an internet connection is needed the first time you configure with this option):

```
cmake -B build -DCMAKE_BUILD_TYPE=Release -DSRR2_FFMPEG_STATIC=ON
cmake --build build -j$(nproc)
```

This only enables the Bink demuxer/decoders the game's `.rmv` movies actually need, so it has no runtime dependency on the system FFmpeg (or anything else) at all - the resulting `SRR2` binary can be copied to another Linux machine, including the Steam Deck, and run as-is. It needs `make` and a C compiler available to build FFmpeg itself. `nasm`/`yasm` are optional (used for x86 asm optimizations); if neither is installed the build falls back automatically to a plain C build, which is fine for the small amount of decoding this needs.

`SRR2_FFMPEG_STATIC` alone isn't enough to run on the Steam Deck if you're building on a distro with a newer glibc than SteamOS ships (e.g. current Fedora) - the binary will fail to load with an error like `GLIBC_2.43 not found`, since glibc only guarantees old binaries run on new systems, not the reverse. Whatever glibc happens to be on the build machine determines the symbol versions every libc/pthread call gets bound to, so this isn't specific to FFmpeg - it affects the whole binary.

To avoid this, build inside Valve's official Sniper SDK container (the same Debian 11-based baseline the Steam Runtime uses), via `docker` or `podman`:

```
./scripts/build-steamdeck.sh
```

This produces `build-steamdeck/code/SRR2`, statically linked against FFmpeg and built against an old-enough glibc/libstdc++ baseline to run on the Deck. Set `CONTAINER_RUNTIME=podman` if you don't have Docker.

### Running

As with the console ports, this build uses the PC release's assets rather than the leaked source code's assets. Copy the contents of the PC installation folder (`art`, `movies`, etc., using the original `.rmv` movie files) alongside the `SRR2` binary, then run it from that directory.
