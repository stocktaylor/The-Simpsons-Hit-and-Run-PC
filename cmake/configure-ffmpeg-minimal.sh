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
# Usage: configure-ffmpeg-minimal.sh <ffmpeg-source-dir> <install-prefix> [cross-prefix] [arch] [cc] [target-os]
#
# <cross-prefix>, if given (e.g. "x86_64-w64-mingw32-"), cross-compiles
# FFmpeg using that toolchain prefix instead of building for the host.
#
# <arch>, if given, overrides the target arch passed to --arch (default
# x86_64) - needed for e.g. aarch64.
#
# <cc>, if given, overrides the C compiler passed to --cc instead of
# configure's own default of "${cross-prefix}gcc" - needed when the cross
# toolchain's compiler isn't named "*-gcc", e.g. llvm-mingw's "*-clang", or
# when it needs extra flags, e.g. "clang --target=aarch64-linux-gnu".
#
# <target-os>, if given, overrides the --target-os passed to configure when
# cross-compiling (default "mingw32", matching every cross target this
# script supported before aarch64 Linux existed) - a native ELF target like
# Linux needs "linux" here instead.

set -e

SRC_DIR="$1"
PREFIX="$2"
CROSS_PREFIX="$3"
ARCH="${4:-x86_64}"
CC="$5"
TARGET_OS="${6:-mingw32}"

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

# Built up via `set --` rather than a flat string: $CC can itself contain
# spaces (e.g. "clang --target=aarch64-linux-gnu"), and a flat string
# re-splits on every space when it's later expanded unquoted, turning that
# back into two separate ./configure arguments instead of one --cc= value -
# `set --` preserves each argument's own boundaries regardless of what's
# inside it.
set -- \
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
	--enable-avformat \
	--enable-avcodec \
	--enable-avutil \
	--enable-swresample \
	--enable-swscale \
	--enable-decoder="$DECODERS" \
	--enable-demuxer="$DEMUXERS"

# configure hard-fails on x86 if nasm/yasm isn't installed rather than just
# dropping asm optimizations, so detect that ourselves - Bink decoding is
# cheap and doesn't need it. Also skip probing for it under cross-compile:
# a host nasm can't assemble for the target anyway.
if [ -n "$CROSS_PREFIX" ] || ! { command -v nasm >/dev/null 2>&1 || command -v yasm >/dev/null 2>&1; }; then
	set -- "$@" --disable-x86asm
fi

if [ -n "$CROSS_PREFIX" ]; then
	set -- "$@" --enable-cross-compile "--arch=$ARCH" "--target-os=$TARGET_OS" "--cross-prefix=$CROSS_PREFIX"
	if [ -n "$CC" ]; then
		set -- "$@" "--cc=$CC"
	fi
fi

./configure "$@"
