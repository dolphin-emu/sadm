#! /usr/bin/env bash
# Repacks .dmg volumes as .7z archives

function cleanup
{
  rm -r $TMP_DIR $TMP_IMG
}

trap cleanup EXIT

INPUT=$1
OUTPUT=$2
TMP_DIR=$(mktemp -d)
TMP_IMG=$(mktemp)

dmg2img -p 4 $INPUT -o $TMP_IMG &&
7z x $TMP_IMG -o$TMP_DIR -y &&
7z a $OUTPUT $TMP_DIR/* -sdel -mm=copy
