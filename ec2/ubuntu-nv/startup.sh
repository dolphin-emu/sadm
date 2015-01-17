#! /bin/sh

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

cd $(dirname $0)
git fetch origin master
git reset --hard origin/master

python ../killswitch.py killswitch.yml &
