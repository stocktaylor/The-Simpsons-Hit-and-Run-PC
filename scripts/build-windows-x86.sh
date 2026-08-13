#!/bin/sh
# Cross-compiles an SRR2.exe for 64-bit Windows (x86_64) from a Linux host,
# inside a Fedora container.
#
# Two compiler options are available, selected the same way as the other
# build scripts:
#   (default)  Clang, via a downloaded llvm-mingw toolchain (clang/lld +
#              mingw-w64 headers/CRT) - the same toolchain
#              scripts/build-windows-arm.sh uses, since that target has no
#              GCC-based alternative at all (see that script for why).
#              Defaulting to it here too keeps one compiler consistent
#              across the Linux and Windows builds. zlib/libpng/SDL2/OpenAL
#              Soft are cross-compiled from source into this toolchain,
#              since none of them are available prebuilt for it.
#   --gcc      GCC, via Fedora's mingw64-gcc-c++ cross compiler package and
#              its prebuilt mingw64-SDL2/openal-soft/libpng/zlib packages.
#
# Unlike scripts/build-linux-x86.sh, there's no glibc-baseline concern here
# (a Windows PE binary doesn't link against the host's glibc at all), so
# this doesn't need to be pinned to any particular Windows-side baseline
# image - it just needs a working cross toolchain and matching cross
# libraries for whichever compiler was selected.
#
# This also (re)builds a minimal static FFmpeg (SRR2_FFMPEG_STATIC) cross-
# compiled for mingw via cmake/configure-ffmpeg-minimal.sh's cross-compile
# support, so the .exe has no FFmpeg DLL dependency to ship alongside it.
#
# Requires docker or podman on the host. Output goes to
# build-windows-x86-<compiler>-<release|debug>/.
#
# Usage: build-windows-x86.sh [--debug] [--gcc]
#   --debug   build a Debug build instead of the default Release
#   --gcc     compile with GCC instead of the default Clang

set -e

BUILD_TYPE=Release
COMPILER=clang

for arg in "$@"; do
	case "$arg" in
		--debug) BUILD_TYPE=Debug ;;
		--gcc) COMPILER=gcc ;;
		*)
			echo "error: unknown argument '$arg'" >&2
			echo "usage: $0 [--debug] [--gcc]" >&2
			exit 1
			;;
	esac
done

RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="fedora:latest"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TYPE_LOWER=$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')
BUILD_DIR="build-windows-x86-${COMPILER}-${BUILD_TYPE_LOWER}"

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
	-e COMPILER="$COMPILER" \
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

		# Building FFmpeg (SRR2_FFMPEG_STATIC) needs a working host C
		# compiler for its own build-time tooling, even while cross
		# compiling the target libraries - without one, configure falls
		# back to something that fails the C11 check FFmpeg requires. Needed
		# for both compiler choices below, since this is about host tooling,
		# not the target toolchain.
		dnf install -y --setopt=install_weak_deps=False \
			cmake git pkgconf-pkg-config curl xz \
			gcc gcc-c++

		if [ "$COMPILER" = "gcc" ]; then
			echo "=== Installing mingw64-gcc-c++ and prebuilt mingw64 libraries ==="
			dnf install -y --setopt=install_weak_deps=False \
				mingw64-gcc-c++ mingw64-SDL2 mingw64-openal-soft \
				mingw64-libpng mingw64-zlib

			echo "=== Building SRR2 ==="
			cmake -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
				-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-mingw64.cmake \
				-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
				-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON
			cmake --build "$BUILD_DIR" -j"$(nproc)"
		else
			echo "=== Fetching llvm-mingw ==="
			curl -L -o "/tmp/${LLVM_MINGW_ARCHIVE}" "$LLVM_MINGW_URL"
			mkdir -p /opt/llvm-mingw
			tar -xf "/tmp/${LLVM_MINGW_ARCHIVE}" -C /opt/llvm-mingw --strip-components=1
			rm "/tmp/${LLVM_MINGW_ARCHIVE}"
			export PATH="/opt/llvm-mingw/bin:$PATH"

			TOOLCHAIN_ARGS="-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-llvm-mingw.cmake -DSRR2_MINGW_TARGET_TRIPLE=x86_64-w64-mingw32"
			DEPS_ROOT=/build/build-windows-x86-deps
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
			# libc++.dll/libunwind.dll: llvm-mingws own C++ runtime,
			# dynamically linked by default. libz.dll: zlibs CMakeLists
			# always builds both a static and shared variant regardless of
			# BUILD_SHARED_LIBS, and libpngs find_package(ZLIB) picked the
			# shared import library.
			OUT_DIR="/build/$BUILD_DIR/code"
			cp -v /opt/llvm-mingw/x86_64-w64-mingw32/bin/libc++.dll "$OUT_DIR/"
			cp -v /opt/llvm-mingw/x86_64-w64-mingw32/bin/libunwind.dll "$OUT_DIR/"
			find "$DEPS_PREFIX" -iname "libz.dll" -exec cp -v {} "$OUT_DIR/" \;
		fi
	'

echo "Built: $REPO_ROOT/$BUILD_DIR/code/SRR2.exe"
