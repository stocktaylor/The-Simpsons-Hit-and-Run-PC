#!/bin/sh
# Configures a minimal, statically-linked FFmpeg checkout containing only
# what radmovie's ffmpegmovieplayer needs: demuxing/decoding the original
# Bink (.rmv) movie files. Everything else (external codec libs, network,
# programs, docs) is disabled, so the result has no runtime dependencies
# beyond libc/libm/libpthread.
#
# The exact Bink demuxer/decoder component names have varied across FFmpeg
# releases, so they're discovered from `configure --list-*` rather than
# hardcoded.
#
# Usage: configure-ffmpeg-minimal.sh <ffmpeg-source-dir> <install-prefix> [cross-prefix] [arch] [cc]
#
# <cross-prefix>, if given (e.g. "x86_64-w64-mingw32-"), cross-compiles
# FFmpeg for Windows using that toolchain prefix instead of building for the
# host. Only mingw-w64 cross-prefixes are supported by the --target-os
# choice below.
#
# <arch>, if given, overrides the target arch passed to --arch (default
# x86_64) - needed for e.g. aarch64.
#
# <cc>, if given, overrides the C compiler passed to --cc instead of
# configure's own default of "${cross-prefix}gcc" - needed when the cross
# toolchain's compiler isn't named "*-gcc", e.g. llvm-mingw's "*-clang".

set -e

SRC_DIR="$1"
PREFIX="$2"
CROSS_PREFIX="$3"
ARCH="${4:-x86_64}"
CC="$5"

if [ -z "$SRC_DIR" ] || [ -z "$PREFIX" ]; then
	echo "usage: $0 <ffmpeg-source-dir> <install-prefix> [cross-prefix] [arch] [cc]" >&2
	exit 1
fi

cd "$SRC_DIR"

# --list-decoders/--list-demuxers print names in fixed-width columns, not
# one per line, so the output has to be tokenized before filtering.
DECODERS=$(./configure --list-decoders | tr -s ' \t' '\n' | grep -i '^bink' | paste -sd, -)
DEMUXERS=$(./configure --list-demuxers | tr -s ' \t' '\n' | grep -i '^bink' | paste -sd, -)

if [ -z "$DECODERS" ] || [ -z "$DEMUXERS" ]; then
	echo "error: this FFmpeg checkout has no Bink demuxer/decoders (looked for names starting with 'bink')" >&2
	exit 1
fi

# configure hard-fails on x86 if nasm/yasm isn't installed rather than just
# dropping asm optimizations, so detect that ourselves - Bink decoding is
# cheap and doesn't need it. Also skip probing for it under cross-compile:
# a host nasm can't assemble for the target anyway.
if [ -z "$CROSS_PREFIX" ] && { command -v nasm >/dev/null 2>&1 || command -v yasm >/dev/null 2>&1; }; then
	X86ASM_FLAG=""
else
	X86ASM_FLAG="--disable-x86asm"
fi

CROSS_FLAGS=""
if [ -n "$CROSS_PREFIX" ]; then
	CROSS_FLAGS="--enable-cross-compile --arch=$ARCH --target-os=mingw32 --cross-prefix=$CROSS_PREFIX"
	if [ -n "$CC" ]; then
		CROSS_FLAGS="$CROSS_FLAGS --cc=$CC"
	fi
fi

./configure \
	--prefix="$PREFIX" \
	--disable-everything \
	--disable-shared \
	--enable-static \
	--disable-programs \
	--disable-doc \
	--disable-network \
	--disable-autodetect \
	--disable-avdevice \
	--disable-avfilter \
	--disable-postproc \
	$X86ASM_FLAG \
	$CROSS_FLAGS \
	--enable-avformat \
	--enable-avcodec \
	--enable-avutil \
	--enable-swresample \
	--enable-swscale \
	--enable-decoder="$DECODERS" \
	--enable-demuxer="$DEMUXERS"
