#!/bin/bash

set -e

cd $1

mkdir content

# Extract Windows and Linux archives to subdirectories within the content folder.
7z x *.7z -ocontent/*

# Extract the macOS DMG and do some corrections to remove useless folders.
mkdir content/mac
7z x mac.dmg -omac_tmp
mv mac_tmp/Dolphin/Dolphin.app content/mac/

# Copy the .vdf and add the build number to it.
cp /home/buildbot/bin/steam_build_script.vdf .
sed -i "s/DOLPHIN_BUILD_NUMBER/$2/" steam_build_script.vdf

# Upload to Steam.
# TODO: path to Steamworks SDK and build account username
/path/to/sdk/tools/ContentBuilder/builder_linux/steamcmd.sh +login xyz +run_app_build $1/steam_build_script.vdf +quit
