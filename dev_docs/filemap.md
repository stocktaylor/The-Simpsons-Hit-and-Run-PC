# Game Directory File Map

What in a working install directory (e.g.
`/home/tstock/Games/The Simpsons Hit and Run/`) is actually read by the
binaries this repo builds (`SRR2`/`SRR2_debug`), versus what's a leftover
from the original Windows `Simpsons.exe` or its third-party mod tooling.
Determined by grepping `code/`/`libs/` for the loading paths plus `strings`
on the built binary to confirm which literal filenames it actually
references.

## Required

These are read directly off disk by `sdldrive.cpp`'s loose-file path or by
name from `soundrenderingmanager.cpp`'s cement-library registration. Nothing
here is Bink, DirectSound/EAX, or DirectX — the default build links FFmpeg,
OpenAL, and a statically-linked OpenGL/GLES `pddi` backend instead
(`code/CMakeLists.txt:595-599`, `libs/radsound/src/hal/win32/system.cpp:99-151`,
`libs/pure3d/CMakeLists.txt:118-162`).

| Path | Why |
|---|---|
| `SRR2` / `SRR2_debug` | The built binary itself. Only one is needed to play; keep `SRR2_debug` around if you want debug symbols for crash investigation, otherwise it's disposable. |
| `art/` (all subfolders: `frontend`, `atc`, `nis`, `missions`, `cars`, `chars`, and the loose `*.p3d` files at the top level) | Loaded by path as loose P3D resource files, e.g. `code/presentation/presentation.cpp:1355-1429` for `art/frontend/dynaload/images/*.p3d`. `FeResourceManager.cpp` has no `.rcf` references at all — art is never packed. |
| `scripts/` (`missions/`, `cars/`, `ss.mfk`, `ssi.mfk`) | Loaded by path, e.g. `code/worldsim/vehiclecentral.cpp:918` for `scripts/cars/`. Confirmed via `strings` (`scripts\missions\level0%d\level.mfk`, etc). |
| `sound/` (`accept.rsd`, `scroll.rsd`, `typ/srrtypes.typ`) | Loaded by path from the sound system; confirmed via `strings` (`sound/accept.rsd`, `sound/scroll.rsd`). |
| `movies/*.rmv` | Read directly and demuxed/decoded via FFmpeg (`libs/radmovie/src/common/ffmpegmovieplayer.cpp`), not Bink. Referenced by name in `code/constants/movienames.h:67-97`. |
| `ambience.rcf`, `carsound.rcf`, `dialog.rcf`, `music00.rcf`–`music03.rcf`, `nis.rcf`, `scripts.rcf`, `soundfx.rcf` | Registered by name in `code/sound/soundrenderer/soundrenderingmanager.cpp:754-766`. (`scripts.rcf` here is a sound "cement library," unrelated to the loose `scripts/` folder above, despite the name collision.) |
| `simpsons.ini` | Read/written by `GameConfigManager` (`code/data/config/gameconfigmanager.cpp:31`), same filename and format as the original PC build, via a custom parser — not the Win32 `GetPrivateProfileString` API. |
| `Save1` | Save data, handled through the same `SaveGameInfo`/`GameDataManager` path (`code/data/savegameinfo.cpp`, `code/data/gamedatamanager.cpp`) that exists in this codebase. Byte-for-byte compatibility with the original exe's save format wasn't verified line-by-line, but there's no separate/incompatible save path — worth keeping rather than deleting.

## Not required (leftovers from the original `Simpsons.exe` / mod tooling)

Zero references anywhere in `code/` or `libs/` — confirmed by both grep and
`strings` on the built binary.

| Path | Why it's unused |
|---|---|
| `Simpsons.exe` | The original Windows binary. This repo's binary replaces it entirely. |
| `Simpsons.dxvk-cache` | DXVK's shader cache for translating `Simpsons.exe`'s Direct3D calls to Vulkan (relevant only when running the original exe under Wine/Proton). This build never uses Direct3D or DXVK. |
| `Lucas Simpsons Hit & Run Mod Launcher.exe` + `Lucas Simpsons Hit & Run Mod Launcher.exe.config` | Third-party .NET mod-loading tool for the original exe. |
| `Mods/*.lmlm` | Mod files consumed by the Mod Launcher above. No "Mods", "lmlm", or mod-loading code anywhere in this repo. |
| `DLLs/` (`zlib.dll`, `ssl-44.dll`, `curl.dll`, `cacert.pem`, `Hacks.dll`, `dbghelp.dll`, `crypto-42.dll`, `GfeSDK.dll`) | Dependencies of the Mod Launcher / original exe (curl+SSL for updates, `Hacks.dll`/`GfeSDK.dll` for mod hooking and Nvidia overlay integration, `dbghelp.dll` for the original's crash handler). Not Linux libraries in the first place — this build is a native ELF binary and can't load Windows DLLs at all. |
| `binkw32.dll` | Bink Video decoder for the original exe. This build's default `SRR2_USE_BINK=OFF` links FFmpeg instead (`CMakeLists.txt:23`); the Bink path is opt-in and not what `SRR2`/`SRR2_debug` were built with. |
| `eax.dll` | Creative EAX/DirectSound reverb library for the original exe. This build implements the equivalent effects through OpenAL EFX calls (`libs/radsound/src/hal/win32/effect.cpp:247`). |
| `pddidx8r.dll` | The original exe's dynamically-loaded DirectX 8 render plugin. This build statically links its `pddi` renderer against OpenGL/GLES instead — no DX8 path is compiled in. |
| `procmon.CSV` | A Windows Process Monitor export sitting in the folder — unrelated to the game itself (looks like leftover output from diagnosing the original exe's DLL loads). |

## Caveats

- This only covers the default desktop Linux build configuration
  (`SRR2_USE_BINK=OFF`, OpenGL/GLES `pddi`, OpenAL). A build with different
  CMake options (e.g. `SRR2_USE_BINK=ON`) would change the `binkw32.dll`/FFmpeg
  conclusion.
- Only `dialog.rcf` (English) exists in this install. The sound code also
  knows how to load `dialogf.rcf`/`dialogg.rcf`/`dialogs.rcf`/`dialogi.rcf`
  (or numbered `dialog0?.rcf` variants) for other languages
  (`soundrenderingmanager.cpp:171-185`) — add those only if you need
  non-English dialogue.
- `Save1` compatibility is a "no evidence against it" conclusion, not a
  verified byte-for-byte match — back it up before relying on it.
