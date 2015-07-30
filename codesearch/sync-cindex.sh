#! /bin/bash

set -e

if [[ "$#" != 3 ]]; then
    echo >&2 "usage: $0 <cindex-file> <user@server> <remote-path>"
    exit 1
fi

LOCAL_PATH=$1
SERVER=$2
REMOTE_PATH=$3

newfname=$(mktemp -u cindex.XXXXXXXX)
baseremotepath=$(dirname "${REMOTE_PATH}")
newfpath="${baseremotepath}/${newfname}"

rsync -avz "${LOCAL_PATH}" "${SERVER}:${newfpath}"
ssh "${SERVER}" "mv -vf \"${newfpath}\" \"${REMOTE_PATH}\""
