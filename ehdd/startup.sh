#!/bin/bash
ehdd/mount.sh || exit 1

if [ -e /etc/cloudinabox.conf ]; then
    systemctl start redis-server
    #redis-cli -s /var/run/redis/redis-server.sock flushall
    systemctl restart fail2ban
    systemctl start php7.2-fpm
    systemctl start mariadb
    systemctl start nginx
    systemctl start cron
fi
