#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

say "Installing redis"
apt_install redis-server php-redis php-apcu || die "Unable to install redis packages"

# enable redis's local Unix socket (for redis on same server as nextcloud)

tools/editconf.py /etc/redis/redis.conf -s \
   "unixsocket=/var/run/redis/redis-server.sock" \
   "unixsocketperm=770"
[ $? -ne 0 ] && die "Unable to edit /etc/redis/redis.conf"

# restart redis

systemctl restart redis-server

# flush all keys

redis-cli flushall >/dev/null 2>&1

true
