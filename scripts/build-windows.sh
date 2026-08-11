#!/bin/sh
# Cross-compiles an SRR2.exe for 64-bit Windows using MinGW-w64, from a
# Linux host, by compiling inside a Fedora container that has the
# mingw64-* cross-compiler and cross libraries available.
#
# Unlike scripts/build-steamdeck.sh, there's no glibc-baseline concern here
# (a Windows PE binary doesn't link against the host's glibc at all), so
# this doesn't need to be pinned to any particular Windows-side baseline
# image - it just needs a mingw64 cross-compiler and matching cross
# libraries, which Fedora packages directly.
#
# This also (re)builds a minimal static FFmpeg (SRR2_FFMPEG_STATIC) cross-
# compiled for mingw via cmake/configure-ffmpeg-minimal.sh's cross-compile
# support, so the .exe has no FFmpeg DLL dependency to ship alongside it.
#
# Requires docker or podman on the host. Output goes to build-windows/.

set -e

RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="fedora:latest"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
	echo "error: '$RUNTIME' not found. Install Docker or Podman, or set CONTAINER_RUNTIME=podman." >&2
	exit 1
fi

"$RUNTIME" run --rm \
	-v "$REPO_ROOT:/build:Z" \
	-w /build \
	"$IMAGE" \
	sh -c '
		set -e
		dnf install -y --setopt=install_weak_deps=False \
			cmake git pkgconf-pkg-config \
			gcc gcc-c++ \
			mingw64-gcc-c++ mingw64-SDL2 mingw64-openal-soft \
			mingw64-libpng mingw64-zlib
		# Building FFmpeg (SRR2_FFMPEG_STATIC) needs a working host C
		# compiler for its own build-time tooling, even while cross
		# compiling the target libraries with mingw64-gcc-c++ - without
		# one, configure falls back to something that fails the C11
		# check FFmpeg requires.
		cmake -B build-windows -DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-mingw64.cmake \
			-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
			-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON
		cmake --build build-windows -j"$(nproc)"
	'

echo "Built: $REPO_ROOT/build-windows/code/SRR2.exe"
