#!/bin/bash

set -e

BUILD_ACCOUNT_PASSWORD=$(cat /path/to/password)

mkdir $1/content

# Windows

7z x $1/win.7z -o$1/content/win -xr\!"Updater.exe" -xr\!"build_info.txt"
mv $1/content/win/Dolphin-x64/* $1/content/win/
rm -r $1/content/win/Dolphin-x64

# Linux

7z x $1/lin.7z -o$1/content/lin -xr\!"Tests" -xr\!"traversal_server"
mv $1/content/lin/Binaries/* $1/content/lin/
rm -r $1/content/lin/Binaries

# macOS

7z x $1/mac.dmg -o$1/content/mac -xr\!"*HFS+ Private*"
mv $1/content/mac/Dolphin/* $1/content/mac/
rm -r $1/content/mac/Dolphin

# Upload

sed "s/DOLPHIN_BUILD_NUMBER/$2/" /home/buildbot/bin/steampipe_app_build.vdf > $1/steampipe_app_build.vdf

/path/to/sdk/tools/ContentBuilder/builder_linux/steamcmd.sh +login username $BUILD_ACCOUNT_PASSWORD +run_app_build $1/steampipe_app_build.vdf +quit
