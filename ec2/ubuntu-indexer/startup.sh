#! /bin/sh

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

cd $(dirname $0)
git fetch origin master
git reset --hard origin/master

# TODO(delroth): Enable once more testing has been done.
# python ../killswitch.py killswitch.yml &

su - ubuntu -c "kythe-install.sh"
su - ubuntu -c "cd /home/ubuntu/buildslave && buildslave start"
