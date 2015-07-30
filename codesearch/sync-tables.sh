#! /bin/bash

set -e

if [[ "$#" != 3 ]]; then
    echo >&2 "usage: $0 <tables-dir> <user@server> <remote-path>"
    exit 1
fi

LOCAL_PATH=$1
SERVER=$2
REMOTE_PATH=$3

newdirname=$(mktemp -u tables.XXXXXXXX)
baseremotepath=$(dirname "${REMOTE_PATH}")
newdirpath="${baseremotepath}/${newdirname}"

rsync -avz "${LOCAL_PATH}/" "${SERVER}:${newdirpath}/"
ssh "${SERVER}" "d=\$(readlink \"${REMOTE_PATH}\"); ln -nsf \"${newdirpath}\" \"${REMOTE_PATH}\"; rm -rf \"\${d}\""
