#!/bin/bash
if [ -s /etc/cloudinabox.conf ]; then
    . /etc/cloudinabox.conf
    . setup/functions.sh
    php="$REQUIRED_PHP_PACKAGE"
    systemctl stop nginx
    systemctl stop $php-fpm
    systemctl stop redis-server
    systemctl stop mariadb
    systemctl stop cron
fi

if [ "$1" != "--no-umount" ]; then
    ehdd/umount.sh
fi
