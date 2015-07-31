#! /bin/sh

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

cd $(dirname $0)

python ../killswitch.py killswitch.yml &

su - ubuntu -c "cd sadm && git fetch origin master && git reset --hard origin/master"
su - ubuntu -c "kythe-install.sh"
su - ubuntu -c "cd buildslave && buildslave start"
