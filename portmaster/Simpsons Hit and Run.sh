#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/$directory/ports/simpsonshitandrun"

mkdir -p "$GAMEDIR"
cd "$GAMEDIR" || exit 1

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# SRR2 uses the PC release's assets, not anything from the leaked source
# code - see the main README.md. ambience.rcf is one of the smaller files
# from that install and always present, so it's a cheap way to check the
# user has actually copied their data in here yet rather than let the
# binary fail on it with a much less obvious error.
if [ ! -f "$GAMEDIR/ambience.rcf" ]; then
	echo "Game data not found in $GAMEDIR"
	echo "Copy your PC installation's art, movies, sound, scripts folders and .rcf files here (using the original .rmv movie files, not converted .bk2 ones), then relaunch."
	pm_finish
	exit 1
fi

# SRR2's own first-run default, when no simpsons.ini exists yet, is 800x600
# windowed (code/main/win32platform.cpp) - a size picked with no awareness
# of the actual display, which can be larger than a handheld's real screen.
# 640x480 is the smallest of the engine's fixed resolution presets (see the
# same file's Resolution enum - it doesn't support arbitrary sizes) and
# matches a lot of this device class's native resolution outright; running
# fullscreen makes more sense than "windowed" on hardware with no window
# manager to give that distinction meaning. This is skipped once a
# simpsons.ini already exists (e.g. a previous run, or you edited it
# yourself), so it never overwrites your own settings or in-game changes.
if [ ! -f "$GAMEDIR/simpsons.ini" ]; then
	cat > "$GAMEDIR/simpsons.ini" <<-EOF
	#System
	display=fullscreen
	resolution=640x480
	bpp=32
	gamma=1.000000
	frameratecap=60
	EOF
fi

# Nothing is bundled/LD_LIBRARY_PATH-overridden here: SRR2 just uses the
# device's own system libraries (SDL2, libpng, OpenAL) directly. An earlier
# version bundled libpng/OpenAL and prioritized them via LD_LIBRARY_PATH,
# on the theory that they weren't guaranteed present the way PortMaster
# guarantees SDL2 is - tested on a real ROCKNIX device, that broke startup
# entirely: the bundled OpenAL (built on Debian bullseye with the sndio
# backend enabled) pulled in a libsndio.so.7.0 dependency ROCKNIX's image
# doesn't have, while ROCKNIX's own OpenAL - which the binary happily uses
# when nothing overrides the library search path - works fine.

# SRR2 reads real SDL gamepad button/axis state directly for gameplay
# (steering, gas, brake, etc. - see libs/radcore/src/radcontroller/sdlcontroller.cpp)
# rather than keyboard/mouse, so this needs a correct SDL_GAMECONTROLLERCONFIG
# for the device's controller, not gptokeyb.
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

pm_platform_helper "$GAMEDIR/SRR2"
./SRR2

pm_finish
