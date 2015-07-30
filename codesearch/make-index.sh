#! /bin/bash

if [[ "$#" != 3 ]]; then
    echo >&2 "usage: $0 <pack-dir> <claims-file> <graphstore-dir>"
    exit 1
fi

export GOMAXPROCS=16

time find "$1/units" -type f -printf "%f\n" | \
    cut -d . -f 1 | \
    sort -R | \
    {
        parallel --gnu -t -L1 \
            indexer -ignore_unimplemented=true -index_pack "$1" -static_claim "$2" || \
        echo "$? failures" >&2
    } | \
    dedup_stream --cache_size=8GiB | \
    write_entries --workers=12 --graphstore "$3"
