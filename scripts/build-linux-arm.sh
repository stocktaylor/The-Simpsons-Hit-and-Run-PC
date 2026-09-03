#!/bin/sh
# Cross-compiles an SRR2 binary for aarch64 Linux from an x86_64 host, using
# Debian's multiarch cross toolchain (crossbuild-essential-arm64) inside an
# ordinary x86_64 Debian 11 (bullseye) container - no QEMU/binfmt involved.
#
# An earlier version of this script instead ran a QEMU-emulated arm64
# container (via `docker run --platform linux/arm64/v8 ...`) and compiled
# natively inside it, which needed binfmt_misc registered on the host *and*
# turned out to need a manual SELinux fcontext fix on Fedora hosts even
# after that (the Fedora qemu-user-static package doesn't ship a policy
# rule labeling /usr/bin/qemu-aarch64-static as qemu_exec_t, which rootless
# podman's confined containers require to exec through it - see git history
# for the fcontext rule that would have fixed it). That's a lot of
# host-environment configuration for what should be a build script, so this
# cross-compiles instead: the container runs as plain x86_64, so none of
# that is needed on the host at all - just docker or podman.
#
# Debian's main archive (unlike Ubuntu's, which splits non-amd64/i386 onto
# ports.ubuntu.com) carries arm64 packages in the same pool as amd64, so
# `dpkg --add-architecture arm64` + apt install <pkg>:arm64 pulls prebuilt
# aarch64 SDL2/libpng/OpenAL straight from the default sources, no
# sources.list surgery needed. There is still no Valve Sniper SDK image for
# arm64 to build against (checked the registry directly: every published
# tag is amd64-only as of this writing) - Valve may eventually ship one
# (their upcoming Steam Frame headset is arm64-based), which would be worth
# switching to for the same glibc-baseline reasoning build-linux-x86.sh
# gives for its own image choice.
#
# This also cross-compiles the vendored static FFmpeg (SRR2_FFMPEG_STATIC)
# using the same aarch64-linux-gnu- toolchain, via the cross-compile support
# cmake/FFmpegStatic.cmake and cmake/configure-ffmpeg-minimal.sh already had
# for the mingw targets, generalized to a native ELF target here.
#
# GCC, not Clang, is the default here - the reverse of every other build
# script. aarch64-linux-gnu-g++ is a complete, self-contained cross
# compiler with every include/library path baked in at build time, so it
# needs nothing extra. Clang cross-compiling via `-target aarch64-linux-gnu`
# instead relies on autodetecting that GCC installation to borrow its
# runtime from, and in testing that detection found the generic libstdc++
# headers but not the target-specific bits/c++config.h - a real gap
# somewhere in how Debian's crossbuild-essential-arm64 package lays things
# out vs. what Clang's Generic_GCC toolchain detection expects, not
# something worth guessing at further with -isystem flags rather than
# fixing at the source. --clang is still available if you want to poke at
# it, but expect that same error.
#
# This is a first attempt at this target - nobody has built or run this
# combination before, so expect this to need iteration.
#
# Requires docker or podman on the host. Output goes to
# build-linux-arm-<compiler>-<release|debug>[-gles2]/.
#
# Usage: build-linux-arm.sh [--debug] [--clang] [--gles2]
#   --debug   build a Debug build instead of the default Release
#   --clang   compile with Clang instead of the default GCC (currently
#             broken - see above)
#   --gles2   build the GLES2 PDDI backend instead of the default desktop
#             OpenGL one (see libs/pure3d/pddi/gles) - this is the backend
#             build-portmaster.sh always uses, since PortMaster devices have
#             no full desktop OpenGL

set -e

BUILD_TYPE=Release
COMPILER=gcc
PDDI=OpenGL

for arg in "$@"; do
	case "$arg" in
		--debug) BUILD_TYPE=Debug ;;
		--clang) COMPILER=clang ;;
		--gles2) PDDI=GLES2 ;;
		*)
			echo "error: unknown argument '$arg'" >&2
			echo "usage: $0 [--debug] [--clang] [--gles2]" >&2
			exit 1
			;;
	esac
done

# --platform linux/amd64 below is passed explicitly even though this
# container just runs as the host's own architecture: without it, a locally
# cached arm64 image under this same name:tag (e.g. left over from an
# earlier QEMU-based version of this script) gets reused instead of pulling
# the amd64 one, and the container fails to start at all ("exec format
# error") since nothing in it can execute on an amd64 host.
RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="docker.io/library/debian:bullseye"
TRIPLE="aarch64-linux-gnu"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TYPE_LOWER=$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')
BUILD_DIR="build-linux-arm-${COMPILER}-${BUILD_TYPE_LOWER}"
if [ "$PDDI" = "GLES2" ]; then
	BUILD_DIR="${BUILD_DIR}-gles2"
fi

if [ "$COMPILER" = "clang" ]; then
	# crossbuild-essential-arm64 (not a separate g++ package) provides the
	# cross libstdc++ Clang needs, via its own g++-aarch64-linux-gnu
	# dependency - same "clang needs libstdc++-dev too" reasoning as
	# build-linux-x86.sh, just satisfied by a different package here.
	CC_PACKAGES="clang crossbuild-essential-arm64"
	CMAKE_COMPILER_ARGS="-DCMAKE_C_COMPILER=clang -DCMAKE_C_COMPILER_TARGET=${TRIPLE} -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE}"
	# FFmpeg's ./configure defaults --cc to "${cross-prefix}gcc", which
	# doesn't exist when Clang was selected - see toolchain-aarch64-linux.cmake.
	SRR2_LINUX_CROSS_CC="clang --target=${TRIPLE}"
else
	CC_PACKAGES="crossbuild-essential-arm64"
	CMAKE_COMPILER_ARGS="-DCMAKE_C_COMPILER=${TRIPLE}-gcc -DCMAKE_CXX_COMPILER=${TRIPLE}-g++"
	SRR2_LINUX_CROSS_CC=""
fi

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
	echo "error: '$RUNTIME' not found. Install Docker or Podman, or set CONTAINER_RUNTIME=podman." >&2
	exit 1
fi

"$RUNTIME" run --rm \
	--platform linux/amd64 \
	-v "$REPO_ROOT:/build:Z" \
	-w /build \
	-e CC_PACKAGES="$CC_PACKAGES" \
	-e CMAKE_COMPILER_ARGS="$CMAKE_COMPILER_ARGS" \
	-e SRR2_LINUX_CROSS_CC="$SRR2_LINUX_CROSS_CC" \
	-e BUILD_TYPE="$BUILD_TYPE" \
	-e BUILD_DIR="$BUILD_DIR" \
	-e PDDI="$PDDI" \
	"$IMAGE" \
	sh -c '
		set -e
		dpkg --add-architecture arm64
		apt-get update
		# build-essential (host gcc/g++/make, not the aarch64 cross ones) is
		# for SRR2_FFMPEG_STATIC specifically: FFmpeg'\''s ./configure builds a
		# few of its own build-time helper programs with a *host* compiler
		# even while cross-compiling everything else, and without one it
		# fails with "Host compiler lacks C11 support" rather than a clearer
		# "no compiler found" - build-windows-x86.sh installs a host gcc for
		# the exact same reason.
		apt-get install -y --no-install-recommends \
			cmake git pkg-config ca-certificates build-essential \
			libsdl2-dev:arm64 libpng-dev:arm64 libopenal-dev:arm64 \
			$CC_PACKAGES
		cmake -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
			-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-aarch64-linux.cmake \
			-DSRR2_LINUX_CROSS_CC="$SRR2_LINUX_CROSS_CC" \
			$CMAKE_COMPILER_ARGS \
			-DSRR2_P3D_PDDI="$PDDI" \
			-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
			-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON
		cmake --build "$BUILD_DIR" -j"$(nproc)"
	'

echo "Built: $REPO_ROOT/$BUILD_DIR/code/SRR2"
