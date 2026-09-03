#!/bin/sh
# Builds an SRR2 binary for x86_64 Linux by compiling inside Valve's
# official Sniper SDK container (Debian 11-based) instead of the host's own
# toolchain.
#
# Why: glibc only guarantees old binaries run on new systems, never the
# reverse. Building natively on a host with a newer glibc than this
# container's baseline (e.g. current Fedora) produces a binary that
# requires glibc symbol versions older systems don't have ("GLIBC_2.43 not
# found" etc.), even for ordinary calls like sqrtf/pthread_create - whatever
# the build machine's glibc happens to be determines the symbol versions
# every call gets bound to. Building inside a fixed, older-baseline
# container keeps the binary portable across modern x86_64 Linux systems,
# including the Steam Deck, which uses this same Sniper baseline for the
# Steam Runtime games run inside on it.
#
# This also (re)builds the vendored static FFmpeg (SRR2_FFMPEG_STATIC) from
# inside the container, so that doesn't reintroduce the same glibc mismatch
# through its own object code.
#
# Requires docker or podman on the host. Output goes to
# build-linux-x86-<compiler>-<release|debug>[-gles2]/.
#
# Usage: build-linux-x86.sh [--debug] [--gcc] [--gles2]
#   --debug   build a Debug build instead of the default Release
#   --gcc     compile with GCC instead of the default Clang
#   --gles2   build the GLES2 PDDI backend instead of the default desktop
#             OpenGL one (see libs/pure3d/pddi/gles) - useful for testing
#             the same rendering backend build-portmaster.sh uses, without
#             its cross-architecture container overhead

set -e

BUILD_TYPE=Release
COMPILER=clang
PDDI=OpenGL

for arg in "$@"; do
	case "$arg" in
		--debug) BUILD_TYPE=Debug ;;
		--gcc) COMPILER=gcc ;;
		--gles2) PDDI=GLES2 ;;
		*)
			echo "error: unknown argument '$arg'" >&2
			echo "usage: $0 [--debug] [--gcc] [--gles2]" >&2
			exit 1
			;;
	esac
done

RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="registry.gitlab.steamos.cloud/steamrt/sniper/sdk"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_TYPE_LOWER=$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')
BUILD_DIR="build-linux-x86-${COMPILER}-${BUILD_TYPE_LOWER}"
if [ "$PDDI" = "GLES2" ]; then
	BUILD_DIR="${BUILD_DIR}-gles2"
fi

if [ "$COMPILER" = "clang" ]; then
	# g++ isn't invoked (CMAKE_C/CXX_COMPILER below still pin clang/clang++)
	# - it's here so apt resolves a concrete, matching libstdc++-<N>-dev for
	# it, which Clang also needs since it uses libstdc++ as its C++ standard
	# library by default on Linux. "libstdc++-dev" alone doesn't work here:
	# Sniper's repo has several versioned providers (libstdc++-14-dev,
	# -10-dev, -9-dev) and nothing to pick one without a package depending on
	# a specific version, the way g++ does.
	CC_PACKAGES="clang g++"
	CMAKE_COMPILER_ARGS="-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
else
	CC_PACKAGES="g++"
	CMAKE_COMPILER_ARGS="-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
fi

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
	echo "error: '$RUNTIME' not found. Install Docker or Podman, or set CONTAINER_RUNTIME=podman." >&2
	exit 1
fi

"$RUNTIME" run --rm \
	-v "$REPO_ROOT:/build:Z" \
	-w /build \
	-e CC_PACKAGES="$CC_PACKAGES" \
	-e CMAKE_COMPILER_ARGS="$CMAKE_COMPILER_ARGS" \
	-e BUILD_TYPE="$BUILD_TYPE" \
	-e BUILD_DIR="$BUILD_DIR" \
	-e PDDI="$PDDI" \
	"$IMAGE" \
	sh -c '
		set -e
		apt-get update
		# Sniper ships SDL2 as libsdl2-compat(-dev), an SDL2 API/ABI shim
		# backed by SDL3, pre-installed by default. Its libsdl2-compat-shim
		# package conflicts with the "classic" libsdl2-2.0-0/libsdl2-dev, so
		# do not request libsdl2-dev - it is already provided.
		apt-get install -y --no-install-recommends \
			cmake git pkg-config ca-certificates \
			libpng-dev libopenal-dev $CC_PACKAGES
		# Force the SDL2 codepath rather than a native SDL3 package: the code
		# targets an older SDL3 API than current SDL3 releases ship, which
		# causes build errors if SDL3 is picked up instead.
		cmake -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
			$CMAKE_COMPILER_ARGS \
			-DSRR2_P3D_PDDI="$PDDI" \
			-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
			-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON
		cmake --build "$BUILD_DIR" -j"$(nproc)"
	'

echo "Built: $REPO_ROOT/$BUILD_DIR/code/SRR2"
