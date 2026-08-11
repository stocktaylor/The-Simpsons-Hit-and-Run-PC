# CMake toolchain file for cross-compiling SRR2 to 64-bit Windows using
# MinGW-w64, from a Linux host. Use with:
#   cmake -B build-windows -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-mingw64.cmake ...
#
# See scripts/build-windows.sh for a full build using this file inside a
# container with the required mingw64-* packages installed.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Also used by FFmpegStatic.cmake to cross-compile FFmpeg itself with the
# same toolchain, since FFmpeg's own ./configure needs an explicit
# --cross-prefix rather than picking this up from CMake.
set(SRR2_MINGW_CROSS_PREFIX "x86_64-w64-mingw32-")

set(CMAKE_C_COMPILER   ${SRR2_MINGW_CROSS_PREFIX}gcc)
set(CMAKE_CXX_COMPILER ${SRR2_MINGW_CROSS_PREFIX}g++)
set(CMAKE_RC_COMPILER  ${SRR2_MINGW_CROSS_PREFIX}windres)

# Fedora's mingw64-* packages (headers, import libs, CMake/pkg-config files
# for SDL2/libpng/OpenAL/zlib) install under this sysroot.
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32/sys-root/mingw)

# Only ever use the mingw sysroot for libraries/headers/package files, never
# accidentally pick up something from the host's own /usr - but do allow
# resolving plain host programs (e.g. a host `git` invoked by
# ExternalProject_Add for SRR2_FFMPEG_STATIC).
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
