#! /bin/sh

su - ubuntu -c "cd /home/ubuntu/buildslave && buildslave stop"
/sbin/halt
