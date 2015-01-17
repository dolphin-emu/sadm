#! /bin/sh

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

cd $(dirname $0)
git fetch origin master
git reset --hard origin/master

openvpn --config openvpn.conf --daemon
i=0
while ! ip l | grep tap0; do
  sleep 1
  i=$((i+1))
  if [ "$i" -gt 60 ]; then
    halt
  fi
done
ip l set tap0 mtu 1400

for host in fifoci buildbot dl; do
  echo "192.168.150.100 $host.dolphin-emu.org" >> /etc/hosts
done

python ../killswitch.py killswitch.yml &

su - ubuntu -c "cd /home/ubuntu/buildslave && buildslave start"
