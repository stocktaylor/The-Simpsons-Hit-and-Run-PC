#!/bin/sh
# Cross-compiles an SRR2 binary targeting PortMaster
# (https://portmaster.games/), the handheld-emulation-device porting
# platform. This is build-linux-arm.sh's cross-compile setup, but defaults
# to the GLES2 PDDI backend (libs/pure3d/pddi/gles) instead of desktop
# OpenGL, since PortMaster's target devices (old-kernel ARM handhelds with
# proprietary Mali drivers) have no full desktop OpenGL - only OpenGL ES
# 2.0/GLES via GL4ES is available there. There's no --gles2/--opengl switch
# here since GLES2 isn't optional on this target the way it's an opt-in
# experiment on build-linux-arm.sh. This also passes -DSRR2_PORTMASTER=ON
# (see CMakeLists.txt), which enables holding Start+Select together to quit
# the game - the convention most other PortMaster ports follow, since these
# handhelds have no keyboard/window to close otherwise.
#
# An earlier version of this script (and build-linux-arm.sh) instead ran a
# QEMU-emulated arm64 Ubuntu 20.04 container - Ubuntu 20.04 LTS aarch64 is
# PortMaster's own documented reference toolchain, so that was a deliberate
# choice to match it as closely as possible. In practice it needed
# binfmt_misc registered on the host *and* a manual SELinux fcontext fix on
# Fedora hosts even after that (see build-linux-arm.sh's comments), which
# was more host-environment configuration than the build itself warranted.
# Cross-compiling avoids all of that - the container runs as plain x86_64 -
# but Ubuntu splits its arm64 packages onto a separate ports.ubuntu.com
# archive that isn't in the default sources.list, which reintroduces its
# own setup cost for a multiarch cross build (see build-linux-arm.sh's
# comments on why Debian's archive layout doesn't have this problem). So
# this reuses build-linux-arm.sh's Debian 11 (bullseye) cross setup
# instead: Debian 11 and Ubuntu 20.04 are close contemporaries (both ship
# glibc 2.31), so this shouldn't meaningfully change binary compatibility
# with PortMaster's actual devices, just how closely the *build environment*
# matches PortMaster's own docs. Revisit this if that assumption turns out
# to matter in practice.
#
# After building, this also assembles a PortMaster package directory at
# build-portmaster-<compiler>-<type>/package/, ready to zip: the versioned
# port.json/launch script from portmaster/, plus the compiled binary. No
# libs.aarch64/ - an earlier version bundled libpng/OpenAL there (with the
# launch script prioritizing it via LD_LIBRARY_PATH) on the theory that
# they weren't guaranteed present on the device the way PortMaster
# guarantees SDL2 is. Tested on a real ROCKNIX device, that theory was
# actively wrong: ROCKNIX already ships a working OpenAL, but the bundled
# one - built on Debian bullseye with the sndio backend enabled - pulled in
# a dependency on libsndio.so.7.0 that ROCKNIX's minimal image doesn't
# have, so prioritizing it over the system's own copy broke startup
# entirely ("error while loading shared libraries"). Running the binary
# directly, without that LD_LIBRARY_PATH override, worked fine. So this
# now relies on the device's own system libraries across the board, same
# as it already did for SDL2. The game's own data isn't included - see
# portmaster/port.json's "inst" field and the main README.md.
#
# GCC, not Clang, is the default here - see build-linux-arm.sh's comments:
# Clang's `-target aarch64-linux-gnu` cross-detection doesn't fully find
# Debian's crossbuild-essential-arm64 header layout (missing
# bits/c++config.h), while aarch64-linux-gnu-g++ needs no extra detection
# at all. --clang is still available if you want to poke at it, but expect
# that same error.
#
# This is a first attempt at this target - nobody has built or run this
# combination before, so expect this to need iteration.
#
# Requires docker or podman on the host. Output goes to
# build-portmaster-<compiler>-<release|debug>/.
#
# Usage: build-portmaster.sh [--debug] [--clang]
#   --debug   build a Debug build instead of the default Release
#   --clang   compile with Clang instead of the default GCC (currently
#             broken - see above)

set -e

BUILD_TYPE=Release
COMPILER=gcc

for arg in "$@"; do
	case "$arg" in
		--debug) BUILD_TYPE=Debug ;;
		--clang) COMPILER=clang ;;
		*)
			echo "error: unknown argument '$arg'" >&2
			echo "usage: $0 [--debug] [--clang]" >&2
			exit 1
			;;
	esac
done

# --platform linux/amd64 below is passed explicitly even though this
# container just runs as the host's own architecture: without it, a locally
# cached arm64 image under this same name:tag (e.g. left over from an
# earlier QEMU-based version of build-linux-arm.sh) gets reused instead of
# pulling the amd64 one, and the container fails to start at all ("exec
# format error") since nothing in it can execute on an amd64 host.
RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="docker.io/library/debian:bullseye"
TRIPLE="aarch64-linux-gnu"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TYPE_LOWER=$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')
BUILD_DIR="build-portmaster-${COMPILER}-${BUILD_TYPE_LOWER}"

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
			-DSRR2_P3D_PDDI=GLES2 \
			-DSRR2_PORTMASTER=ON \
			-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
			-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON
		cmake --build "$BUILD_DIR" -j"$(nproc)"

		echo "=== Assembling PortMaster package ==="
		PKG="$BUILD_DIR/package"
		rm -rf "$PKG"
		mkdir -p "$PKG/simpsonshitandrun"
		cp portmaster/port.json "$PKG/port.json"
		cp "portmaster/Simpsons Hit and Run.sh" "$PKG/Simpsons Hit and Run.sh"
		chmod +x "$PKG/Simpsons Hit and Run.sh"
		cp "$BUILD_DIR/code/SRR2" "$PKG/simpsonshitandrun/SRR2"
		chmod +x "$PKG/simpsonshitandrun/SRR2"
	'

echo "Built: $REPO_ROOT/$BUILD_DIR/code/SRR2"
echo "PortMaster package staged at: $REPO_ROOT/$BUILD_DIR/package/"
echo "Add your copy of the PC release's game data to $BUILD_DIR/package/simpsonshitandrun/ (see portmaster/port.json's \"inst\" field), then zip the package/ directory's contents for PortMaster."
