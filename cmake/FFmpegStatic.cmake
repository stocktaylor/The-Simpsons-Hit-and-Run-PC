# Builds a minimal, statically-linked FFmpeg (Bink playback only, see
# configure-ffmpeg-minimal.sh) as part of the CMake build and exposes it as
# the SRR2::FFmpeg target, so the resulting binary has no libavformat/
# libavcodec/etc. runtime dependency at all.
#
# This is an alternative to the default path (top-level CMakeLists.txt),
# which links against whatever FFmpeg the build machine's package manager
# provides via pkg-config. That's fine on the machine that built it, but the
# exact shared library versions (SONAMEs) it links against aren't guaranteed
# to exist on another machine - e.g. a binary built on Fedora will refuse to
# run on the Steam Deck's SteamOS because the two ship different FFmpeg
# builds, and SteamOS's read-only filesystem means you can't just install a
# matching one.

include(ExternalProject)
include(ProcessorCount)

ProcessorCount(SRR2_FFMPEG_NPROC)
if(SRR2_FFMPEG_NPROC EQUAL 0)
	set(SRR2_FFMPEG_NPROC 1)
endif()

set(SRR2_FFMPEG_STATIC_TAG "n7.1.5" CACHE STRING "FFmpeg git tag to build for SRR2_FFMPEG_STATIC")

set(SRR2_FFMPEG_PREFIX "${CMAKE_BINARY_DIR}/ffmpeg-minimal")

# CMake errors at generate time if an INTERFACE_INCLUDE_DIRECTORIES entry
# doesn't exist yet, which it won't until ffmpeg_minimal has actually built.
file(MAKE_DIRECTORY "${SRR2_FFMPEG_PREFIX}/include")

ExternalProject_Add(ffmpeg_minimal
	GIT_REPOSITORY "https://github.com/FFmpeg/FFmpeg.git"
	GIT_TAG "${SRR2_FFMPEG_STATIC_TAG}"
	GIT_SHALLOW TRUE
	UPDATE_COMMAND ""
	BUILD_IN_SOURCE TRUE
	CONFIGURE_COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/configure-ffmpeg-minimal.sh" <SOURCE_DIR> "${SRR2_FFMPEG_PREFIX}" "${SRR2_MINGW_CROSS_PREFIX}" "${SRR2_MINGW_FFMPEG_ARCH}" "${SRR2_MINGW_FFMPEG_CC}"
	BUILD_COMMAND make -j${SRR2_FFMPEG_NPROC}
	INSTALL_COMMAND make install
	BUILD_BYPRODUCTS
		"${SRR2_FFMPEG_PREFIX}/lib/libavformat.a"
		"${SRR2_FFMPEG_PREFIX}/lib/libavcodec.a"
		"${SRR2_FFMPEG_PREFIX}/lib/libavutil.a"
		"${SRR2_FFMPEG_PREFIX}/lib/libswresample.a"
		"${SRR2_FFMPEG_PREFIX}/lib/libswscale.a"
)

add_library(srr2_ffmpeg_static INTERFACE)
add_dependencies(srr2_ffmpeg_static ffmpeg_minimal)
target_include_directories(srr2_ffmpeg_static INTERFACE "${SRR2_FFMPEG_PREFIX}/include")
target_link_libraries(srr2_ffmpeg_static INTERFACE
	# The five archives reference symbols in each other; --start-group/
	# --end-group lets the linker re-scan them until everything resolves
	# instead of requiring a strict dependency order.
	-Wl,--start-group
	"${SRR2_FFMPEG_PREFIX}/lib/libavformat.a"
	"${SRR2_FFMPEG_PREFIX}/lib/libavcodec.a"
	"${SRR2_FFMPEG_PREFIX}/lib/libswresample.a"
	"${SRR2_FFMPEG_PREFIX}/lib/libswscale.a"
	"${SRR2_FFMPEG_PREFIX}/lib/libavutil.a"
	-Wl,--end-group
	Threads::Threads
	m
)
if(WIN32)
	# libavutil's random_seed.c calls into BCrypt* (bcrypt.dll) for secure
	# random bytes on Windows.
	target_link_libraries(srr2_ffmpeg_static INTERFACE bcrypt)
endif()

add_library(SRR2::FFmpeg ALIAS srr2_ffmpeg_static)
