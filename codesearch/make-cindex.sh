#! /bin/bash

if [[ "$#" != 2 ]]; then
    echo >&2 "usage: $0 <src-dir> <cindex-file>"
    exit 1
fi

export GOMAXPROCS=16
export CSEARCHINDEX=$2
exec cindex "$1"
