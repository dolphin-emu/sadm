#! /usr/bin/env bash

set -e

BASEDIR=$(dirname $(realpath "$0"))

BUILD_ACCOUNT_USERNAME=$(cat "$STEAM_ACCOUNT_USERNAME_PATH")
BUILD_ACCOUNT_PASSWORD=$(cat "$STEAM_ACCOUNT_PASSWORD_PATH")

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

dmg2img -p 4 $1/mac.dmg -o $1/mac.img
7z x $1/mac.img -o$1/content/mac -xr\!"*HFS+ Private*"
mv $1/content/mac/Dolphin/* $1/content/mac/
rm -r $1/content/mac/Dolphin

# Upload

sed "s/DOLPHIN_BUILD_NUMBER/$2/" $BASEDIR/../lib/steampipe_app_build.vdf > $1/steampipe_app_build.vdf

steamcmd +login "$BUILD_ACCOUNT_USERNAME" "$BUILD_ACCOUNT_PASSWORD" +run_app_build $1/steampipe_app_build.vdf +quit
