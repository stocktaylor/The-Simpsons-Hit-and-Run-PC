# CMake toolchain file for cross-compiling SRR2 to aarch64 Linux from an
# x86_64 host, using Debian's multiarch cross toolchain
# (crossbuild-essential-arm64) and target-arch library packages installed
# alongside the host's own via `dpkg --add-architecture arm64` (see
# scripts/build-linux-arm.sh and scripts/build-portmaster.sh, which both use
# this file). Use with:
#   cmake -B build-linux-arm -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-aarch64-linux.cmake \
#       -DCMAKE_C_COMPILER=... -DCMAKE_CXX_COMPILER=... ...
#
# Unlike the mingw toolchain files, the compiler binaries themselves aren't
# set here - CMAKE_C_COMPILER/CMAKE_CXX_COMPILER (and, for Clang,
# CMAKE_C_COMPILER_TARGET/CMAKE_CXX_COMPILER_TARGET) are passed on the cmake
# command line instead, the same way the native (non-cross) Linux build
# scripts already select between GCC and Clang - there's no reason to fix
# the compiler choice into this file when a native ELF target lets both
# compiler families cross-compile with nothing more than a `--target=`
# flag, unlike mingw where each compiler needs its own dedicated toolchain
# file/wrapper binaries.
#
# This also doesn't point CMAKE_FIND_ROOT_PATH at a separate sysroot
# directory the way the mingw toolchain files do: Debian's multiarch cross
# toolchain is built with --with-sysroot=/, specifically so it (and CMake,
# which detects CMAKE_LIBRARY_ARCHITECTURE from the compiler's own reported
# target triple) finds target headers/libs directly under the host's own
# /usr/include, /usr/include/aarch64-linux-gnu, and /usr/lib/aarch64-linux-gnu
# - exactly where apt installs "<pkg>:arm64" packages. There's nothing to
# root-relativize; the host's own /usr already *is* the effective sysroot
# for both architectures at once.
#
# This is a first attempt at this target - nobody has built or run this
# combination before, so expect this to need iteration.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Also used by FFmpegStatic.cmake to cross-compile FFmpeg itself with the
# same toolchain, since FFmpeg's own ./configure needs an explicit
# --cross-prefix rather than picking this up from CMake. The binutils tools
# this resolves (${SRR2_LINUX_CROSS_PREFIX}ar/strip/etc.) come from
# crossbuild-essential-arm64 regardless of which compiler is selected above.
set(SRR2_LINUX_CROSS_PREFIX "aarch64-linux-gnu-")

# FFmpeg's ./configure defaults --cc to "${cross-prefix}gcc", which is only
# right for the GCC build - the Clang build passes this explicitly instead
# (see scripts/build-linux-arm.sh / scripts/build-portmaster.sh) since
# there's no "aarch64-linux-gnu-clang" wrapper binary; plain "clang
# --target=aarch64-linux-gnu" is what cross-compiles with the system Clang.
set(SRR2_LINUX_CROSS_CC "" CACHE STRING
	"--cc value FFmpegStatic.cmake passes to FFmpeg's ./configure; leave empty to use its \"\${cross-prefix}gcc\" default")
