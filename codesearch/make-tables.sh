#! /bin/bash

if [[ "$#" != 2 ]]; then
    echo >&2 "usage: $0 <graphstore-dir> <tables-dir>"
    exit 1
fi

export GOMAXPROCS=16
ulimit -n 65536
exec write_tables -graphstore "$1" -out "$2"
