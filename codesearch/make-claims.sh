#! /bin/bash

if [[ "$#" != 2 ]]; then
    echo >&2 "usage: $0 <pack-dir> <claims-file>"
    exit 1
fi

exec static_claim --index_pack "$1" > "$2"
