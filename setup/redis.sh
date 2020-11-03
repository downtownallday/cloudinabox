#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

if kernel_ipv6_lo_disabled; then
    # travis on ubuntu 18 does not have ip6 on loopback and that
    # causes the installation to fail in the package postinstall
    # script. Deal with that here.
    say "Installing redis the Travis way"
    apt-get install -y redis-server  # ignore error
    if [ $? -ne 0 ]; then
        tools/editconf.py -s /etc/redis/redis.conf "bind=127.0.0.1" || \
            die "could not edit /etc/redis/redis.conf"
        systemctl start redis-server || \
            die "cloud not start redis!"
    fi
    
else
    say "Installing redis"
    apt_install redis-server || die "Unable to install redis-server"
fi

# install redis php packages


apt_install $php-redis $php-apcu || die "Unable to install redis packages"

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
