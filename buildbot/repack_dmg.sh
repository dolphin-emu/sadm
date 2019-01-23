#!/bin/bash
# Repacks .dmg volumes as .7z archives

function cleanup
{
  rm -r $TMP_DIR
}

trap cleanup EXIT

INPUT=$1
OUTPUT=$2
TMP_DIR=$(mktemp -d)

7z x $INPUT -o$TMP_DIR -y &&
7z a $OUTPUT $TMP_DIR/* -sdel -mm=copy
