# Generic CMake toolchain file for cross-compiling SRR2 to Windows using the
# llvm-mingw toolchain (clang/lld + mingw-w64 headers/CRT), from a Linux
# x86_64 host. Shared by scripts/build-windows-x86.sh (Clang, the default
# there) and scripts/build-windows-arm.sh (Clang, the only option there -
# see that script for why there's no GCC alternative). Select the target
# with -DSRR2_MINGW_TARGET_TRIPLE=<triple>, e.g.:
#   -DSRR2_MINGW_TARGET_TRIPLE=x86_64-w64-mingw32
#   -DSRR2_MINGW_TARGET_TRIPLE=aarch64-w64-mingw32

if(NOT SRR2_MINGW_TARGET_TRIPLE)
	message(FATAL_ERROR "SRR2_MINGW_TARGET_TRIPLE must be set, e.g. -DSRR2_MINGW_TARGET_TRIPLE=x86_64-w64-mingw32")
endif()

set(CMAKE_SYSTEM_NAME Windows)
if(SRR2_MINGW_TARGET_TRIPLE STREQUAL "x86_64-w64-mingw32")
	set(CMAKE_SYSTEM_PROCESSOR x86_64)
elseif(SRR2_MINGW_TARGET_TRIPLE STREQUAL "aarch64-w64-mingw32")
	set(CMAKE_SYSTEM_PROCESSOR ARM64)
else()
	message(FATAL_ERROR "toolchain-llvm-mingw.cmake: unrecognized SRR2_MINGW_TARGET_TRIPLE '${SRR2_MINGW_TARGET_TRIPLE}' - add a CMAKE_SYSTEM_PROCESSOR mapping for it")
endif()

# Also used by FFmpegStatic.cmake to cross-compile FFmpeg with the same
# toolchain (FFmpeg's own ./configure needs an explicit --cross-prefix/
# --arch/--cc rather than picking these up from CMake). FFmpeg's --arch
# names happen to match the triple's first component for every target this
# file supports (x86_64, aarch64), so it's derived rather than listed again.
set(SRR2_MINGW_CROSS_PREFIX "${SRR2_MINGW_TARGET_TRIPLE}-")
string(REGEX MATCH "^[^-]+" SRR2_MINGW_FFMPEG_ARCH "${SRR2_MINGW_TARGET_TRIPLE}")

set(SRR2_MINGW_TOOLCHAIN_ROOT "/opt/llvm-mingw" CACHE PATH
	"Root of the extracted llvm-mingw toolchain (see scripts/build-windows-x86.sh / scripts/build-windows-arm.sh)")

set(CMAKE_C_COMPILER   "${SRR2_MINGW_TOOLCHAIN_ROOT}/bin/${SRR2_MINGW_CROSS_PREFIX}clang")
set(CMAKE_CXX_COMPILER "${SRR2_MINGW_TOOLCHAIN_ROOT}/bin/${SRR2_MINGW_CROSS_PREFIX}clang++")
set(CMAKE_RC_COMPILER  "${SRR2_MINGW_TOOLCHAIN_ROOT}/bin/${SRR2_MINGW_CROSS_PREFIX}windres")
set(CMAKE_AR           "${SRR2_MINGW_TOOLCHAIN_ROOT}/bin/${SRR2_MINGW_CROSS_PREFIX}ar" CACHE FILEPATH "")
# Also used directly by configure-ffmpeg-minimal.sh, since FFmpeg's
# ./configure defaults to "${cross_prefix}gcc" as the C compiler name,
# which doesn't exist here - llvm-mingw's C compiler wrapper is named
# "<triple>-clang", not "<triple>-gcc".
set(SRR2_MINGW_FFMPEG_CC "${CMAKE_C_COMPILER}")

# Deliberately not setting CMAKE_SYSROOT: llvm-mingw's <triple>-clang/
# <triple>-clang++ binaries already self-configure correctly via a paired
# clang .cfg file (e.g. bin/aarch64-w64-windows-gnu.cfg) that injects the
# right --target=/-resource-dir/-internal-isystem flags on their own -
# verified directly with `clang++ -v`, which shows a clean search path with
# no host /usr/include involved at all. Adding our own CMAKE_SYSROOT here
# doesn't fix anything (confirmed: it made no observable difference to an
# earlier failure) and risks interfering with that already-correct config.

set(CMAKE_FIND_ROOT_PATH "${SRR2_MINGW_TOOLCHAIN_ROOT}/${SRR2_MINGW_TARGET_TRIPLE}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
# BOTH rather than the Fedora mingw64 toolchain file's ONLY: there's no
# single "sysroot" here containing every dependency the way Fedora's
# mingw64 packages provide one - zlib/libpng/SDL2/OpenAL get built from
# source into an arbitrary CMAKE_PREFIX_PATH location outside
# CMAKE_FIND_ROOT_PATH, so find_package() needs to still consider normal
# (non-root-relative) paths to find them.
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
