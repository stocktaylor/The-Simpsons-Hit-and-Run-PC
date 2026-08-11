#!/bin/sh
# Builds an SRR2 binary compatible with the Steam Deck by compiling inside
# Valve's official Sniper SDK container (Debian 11-based) instead of the
# host's own toolchain.
#
# Why: glibc only guarantees old binaries run on new systems, never the
# reverse. Building natively on a host with a newer glibc than SteamOS ships
# (e.g. current Fedora) produces a binary that requires glibc symbol
# versions the Deck doesn't have ("GLIBC_2.43 not found" etc.), even for
# ordinary calls like sqrtf/pthread_create - whatever the build machine's
# glibc happens to be determines the symbol versions every call gets bound
# to. The Sniper SDK is the same baseline Valve uses for the Steam Runtime
# that games actually run inside on the Deck, so building against it keeps
# the binary within that baseline.
#
# This also (re)builds the vendored static FFmpeg (SRR2_FFMPEG_STATIC) from
# inside the container, so that doesn't reintroduce the same glibc mismatch
# through its own object code.
#
# Requires docker or podman on the host. Output goes to build-steamdeck/.

set -e

RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="registry.gitlab.steamos.cloud/steamrt/sniper/sdk"
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
		apt-get update
		# Sniper ships SDL2 as libsdl2-compat(-dev), an SDL2 API/ABI shim
		# backed by SDL3, pre-installed by default. Its libsdl2-compat-shim
		# package conflicts with the "classic" libsdl2-2.0-0/libsdl2-dev, so
		# do not request libsdl2-dev - it is already provided.
		apt-get install -y --no-install-recommends \
			cmake git pkg-config ca-certificates \
			libpng-dev libopenal-dev
		# Force the SDL2 codepath rather than a native SDL3 package, for the
		# same reason documented in README.md#dependencies: the code targets
		# an older SDL3 API than current SDL3 releases ship.
		cmake -B build-steamdeck -DCMAKE_BUILD_TYPE=Release \
			-DSRR2_FFMPEG_STATIC=ON -DSRR2_BUILD_TESTS=OFF \
			-DCMAKE_DISABLE_FIND_PACKAGE_SDL3=ON
		cmake --build build-steamdeck -j"$(nproc)"
	'

echo "Built: $REPO_ROOT/build-steamdeck/code/SRR2"
