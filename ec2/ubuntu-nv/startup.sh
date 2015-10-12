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

cat > /etc/hosts <<EOF
127.0.0.1 localhost

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF
for host in fifoci buildbot dl; do
  echo "192.168.150.100 $host.dolphin-emu.org" >> /etc/hosts
done

python ../killswitch.py killswitch.yml &

apt-get update
apt-get install ninja-build
rm -rf /home/ubuntu/buildslave/*/build/build

su - ubuntu -c "cd /home/ubuntu/buildslave && buildslave start"
