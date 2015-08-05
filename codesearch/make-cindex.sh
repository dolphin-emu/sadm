#! /bin/bash

if [[ "$#" != 2 ]]; then
    echo >&2 "usage: $0 <tables-dir> <cindex-file>"
    exit 1
fi

export GOMAXPROCS=16
exec csindexer --serving_table "$1" --out "$2"
