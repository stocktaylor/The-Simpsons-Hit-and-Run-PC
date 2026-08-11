# CMake toolchain file for cross-compiling SRR2 to native ARM64 Windows,
# from a Linux x86_64 host, using the llvm-mingw toolchain (clang/lld +
# mingw-w64 headers/CRT) rather than GCC - Fedora's mingw64-* packages only
# target x86_64/i686, not aarch64, so there's no GCC-based mingw cross
# compiler for this target readily available.
#
# See scripts/build-windows-arm64.sh, which downloads llvm-mingw and cross-
# compiles zlib/libpng/SDL2/OpenAL Soft from source (none of them are
# available prebuilt for this target either) before building SRR2 itself.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ARM64)

set(SRR2_MINGW_TARGET_TRIPLE "aarch64-w64-mingw32")
# Also used by FFmpegStatic.cmake to cross-compile FFmpeg with the same
# toolchain (FFmpeg's own ./configure needs an explicit --cross-prefix/
# --arch/--cc rather than picking these up from CMake).
set(SRR2_MINGW_CROSS_PREFIX "${SRR2_MINGW_TARGET_TRIPLE}-")
set(SRR2_MINGW_FFMPEG_ARCH "aarch64")

set(SRR2_MINGW_TOOLCHAIN_ROOT "/opt/llvm-mingw" CACHE PATH
	"Root of the extracted llvm-mingw toolchain (see scripts/build-windows-arm64.sh)")

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
# BOTH rather than the x86_64 toolchain file's ONLY: there's no single
# "sysroot" here containing every dependency the way Fedora's mingw64
# packages provide one - zlib/libpng/SDL2/OpenAL get built from source into
# an arbitrary CMAKE_PREFIX_PATH location outside CMAKE_FIND_ROOT_PATH, so
# find_package() needs to still consider normal (non-root-relative) paths
# to find them.
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
