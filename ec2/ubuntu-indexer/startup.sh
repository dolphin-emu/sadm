#! /bin/sh

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

# Copy EBS data to the ephemeral local SSD.
rm -rf /mnt/home
rsync -aHAX /_mnt/home /mnt

# TODO(delroth): Enable once more testing has been done.
python ../killswitch.py killswitch.yml &

su - ubuntu -c "cd sadm && git fetch origin master && git reset --hard origin/master"
su - ubuntu -c "kythe-install.sh"
su - ubuntu -c "cd buildslave && buildslave start"
