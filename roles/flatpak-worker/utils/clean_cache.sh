#!/bin/bash

DIRECTORY_SIZE=$(du -sb .flatpak-builder | cut -f1)
MAX_SIZE=10737418240 # 10GiB

if [[ $DIRECTORY_SIZE -eq "" ]]; then
    echo "Failed to calculate cache size, bailing out"
    exit 0
fi

if [[ $DIRECTORY_SIZE -gt $MAX_SIZE ]]; then
    echo "Cache is too large ($DIRECTORY_SIZE bytes), clearing"
    rm -rf .flatpak-builder
else
    echo "Cache is still within a reasonable size ($DIRECTORY_SIZE bytes)"
fi
