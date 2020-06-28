#!/bin/bash
if [ -s /etc/cloudinabox.conf ]; then
    systemctl stop nginx
    systemctl stop php7.2-fpm
    systemctl stop redis-server
    systemctl stop mariadb
    systemctl stop cron
fi

ehdd/umount.sh
