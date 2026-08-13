#!/bin/sh
# Cross-compiles an SRR2.exe for native ARM64 Windows, from a Linux x86_64
# host, using the llvm-mingw toolchain (clang/lld + mingw-w64 headers/CRT).
#
# Unlike scripts/build-windows-x86.sh, Fedora doesn't package an
# aarch64-w64-mingw32 cross compiler or any cross-built libraries for it at
# all, so there is no GCC option here - Clang (via llvm-mingw) is the only
# toolchain that can target this architecture. Passing --gcc is rejected
# rather than silently ignored, so a binary claimed as GCC never turns out
# to actually be Clang.
#
# This script:
#   1. Downloads a prebuilt llvm-mingw release (it ships cross compilers for
#      x86_64/i686/armv7/aarch64 all in one toolchain).
#   2. Cross-compiles zlib, libpng, SDL2, and OpenAL Soft from source into a
#      shared prefix, since none of them are available prebuilt for this
#      target either.
#   3. Cross-compiles a minimal static FFmpeg the same way
#      build-windows-x86.sh's Clang build does (SRR2_FFMPEG_STATIC), just
#      re-targeted to aarch64.
#   4. Configures and builds SRR2 itself against all of the above.
#
# This is a first attempt at this target - nobody has built or run this
# combination before, so expect this to need iteration.
#
# Requires docker or podman on the host. Output goes to
# build-windows-arm-clang-<release|debug>/.
#
# Usage: build-windows-arm.sh [--debug]
#   --debug   build a Debug build instead of the default Release

set -e

BUILD_TYPE=Release

for arg in "$@"; do
	case "$arg" in
		--debug) BUILD_TYPE=Debug ;;
		--gcc)
			echo "error: --gcc is not supported for the Windows ARM build." >&2
			echo "There is no GCC-based mingw-w64 cross compiler for aarch64-w64-mingw32 (Fedora only packages one for x86_64/i686) - this target only builds with Clang via llvm-mingw. Run without --gcc." >&2
			exit 1
			;;
		*)
			echo "error: unknown argument '$arg'" >&2
			echo "usage: $0 [--debug]" >&2
			exit 1
			;;
	esac
done

RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="fedora:latest"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TYPE_LOWER=$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')
BUILD_DIR="build-windows-arm-clang-${BUILD_TYPE_LOWER}"

LLVM_MINGW_VERSION="20260616"
LLVM_MINGW_ARCHIVE="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64.tar.xz"
LLVM_MINGW_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${LLVM_MINGW_ARCHIVE}"

ZLIB_TAG="v1.3.2"
LIBPNG_TAG="v1.6.57"
SDL2_TAG="release-2.32.10"
OPENAL_SOFT_TAG="openal-soft-1.21.0"

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
	echo "error: '$RUNTIME' not found. Install Docker or Podman, or set CONTAINER_RUNTIME=podman." >&2
	exit 1
fi

"$RUNTIME" run --rm \
	-v "$REPO_ROOT:/build:Z" \
	-w /build \
	-e BUILD_TYPE="$BUILD_TYPE" \
	-e BUILD_DIR="$BUILD_DIR" \
	-e LLVM_MINGW_URL="$LLVM_MINGW_URL" \
	-e LLVM_MINGW_ARCHIVE="$LLVM_MINGW_ARCHIVE" \
	-e ZLIB_TAG="$ZLIB_TAG" \
	-e LIBPNG_TAG="$LIBPNG_TAG" \
	-e SDL2_TAG="$SDL2_TAG" \
	-e OPENAL_SOFT_TAG="$OPENAL_SOFT_TAG" \
	"$IMAGE" \
	sh -c '
		set -e

		dnf install -y --setopt=install_weak_deps=False \
			cmake git pkgconf-pkg-config curl xz \
			gcc gcc-c++

		echo "=== Fetching llvm-mingw ==="
		curl -L -o "/tmp/${LLVM_MINGW_ARCHIVE}" "$LLVM_MINGW_URL"
		mkdir -p /opt/llvm-mingw
		tar -xf "/tmp/${LLVM_MINGW_ARCHIVE}" -C /opt/llvm-mingw --strip-components=1
		rm "/tmp/${LLVM_MINGW_ARCHIVE}"
		export PATH="/opt/llvm-mingw/bin:$PATH"

		TOOLCHAIN_ARGS="-DCMAKE_TOOLCHAIN_FILE=/build/cmake/toolchain-llvm-mingw.cmake -DSRR2_MINGW_TARGET_TRIPLE=aarch64-w64-mingw32"
		DEPS_ROOT=/build/build-windows-arm-deps
		DEPS_PREFIX="$DEPS_ROOT/prefix"
		mkdir -p "$DEPS_ROOT" "$DEPS_PREFIX"
		cd "$DEPS_ROOT"

		echo "=== Building zlib ($ZLIB_TAG) ==="
		test -d zlib-src || git clone --branch "$ZLIB_TAG" --depth 1 https://github.com/madler/zlib.git zlib-src
		cmake -B zlib-build -S zlib-src \
			$TOOLCHAIN_ARGS \
			-DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
			-DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
			-DCMAKE_BUILD_TYPE=Release \
			-DBUILD_SHARED_LIBS=OFF
		cmake --build zlib-build -j"$(nproc)"
		cmake --install zlib-build

		echo "=== Building libpng ($LIBPNG_TAG) ==="
		test -d libpng-src || git clone --branch "$LIBPNG_TAG" --depth 1 https://github.com/pnggroup/libpng.git libpng-src
		cmake -B libpng-build -S libpng-src \
			$TOOLCHAIN_ARGS \
			-DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
			-DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
			-DCMAKE_BUILD_TYPE=Release \
			-DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
		cmake --build libpng-build -j"$(nproc)"
		cmake --install libpng-build

		echo "=== Building SDL2 ($SDL2_TAG) ==="
		test -d sdl2-src || git clone --branch "$SDL2_TAG" --depth 1 https://github.com/libsdl-org/SDL.git sdl2-src
		cmake -B sdl2-build -S sdl2-src \
			$TOOLCHAIN_ARGS \
			-DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
			-DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
			-DCMAKE_BUILD_TYPE=Release \
			-DSDL_SHARED=OFF -DSDL_STATIC=ON
		cmake --build sdl2-build -j"$(nproc)"
		cmake --install sdl2-build

		echo "=== Building OpenAL Soft ($OPENAL_SOFT_TAG) ==="
		test -d openal-soft-src || git clone --branch "$OPENAL_SOFT_TAG" --depth 1 https://github.com/kcat/openal-soft.git openal-soft-src
		cmake -B openal-soft-build -S openal-soft-src \
			$TOOLCHAIN_ARGS \
			-DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
			-DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
			-DLIBTYPE=STATIC -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
			-DALSOFT_BACKEND_OSS=OFF -DALSOFT_BACKEND_ALSA=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
			-DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF -DALSOFT_BACKEND_SOLARIS=OFF \
			-DALSOFT_BACKEND_SNDIO=OFF
		cmake --build openal-soft-build -j"$(nproc)"
		cmake --install openal-soft-build

		echo "=== Building SRR2 ==="
		cd /build
		cmake -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
			$TOOLCHAIN_ARGS \
			-DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
			-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
			-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON \
			-DSRR2_OPENAL_STATIC=ON
		cmake --build "$BUILD_DIR" -j"$(nproc)"

		echo "=== Copying required runtime DLLs next to SRR2.exe ==="
		# libc++.dll/libunwind.dll: llvm-mingws own C++ runtime, dynamically
		# linked by default. libz.dll: zlibs CMakeLists always builds both a
		# static and shared variant regardless of BUILD_SHARED_LIBS, and
		# libpngs find_package(ZLIB) picked the shared import library.
		# Scoped to the aarch64 triples own bin dir specifically - llvm-mingw
		# ships runtime DLLs for x86_64/i686/armv7/aarch64 all in one archive,
		# each under its own <triple>/bin/, and an unscoped search would match
		# all four and silently overwrite the destination with the wrong
		# architectures copy.
		OUT_DIR="/build/$BUILD_DIR/code"
		cp -v /opt/llvm-mingw/aarch64-w64-mingw32/bin/libc++.dll "$OUT_DIR/"
		cp -v /opt/llvm-mingw/aarch64-w64-mingw32/bin/libunwind.dll "$OUT_DIR/"
		find "$DEPS_PREFIX" -iname "libz.dll" -exec cp -v {} "$OUT_DIR/" \;
	'

echo "Built: $REPO_ROOT/$BUILD_DIR/code/SRR2.exe"
