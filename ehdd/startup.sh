#!/bin/bash

if [ "${1:-}" != "--no-mount" ]; then
    ehdd/mount.sh || exit 1
fi

. ehdd/ehdd_funcs.sh || exit 1

if system_installed_with_encryption_at_rest; then
    . setup/functions.sh
    php="$REQUIRED_PHP_PACKAGE"
    systemctl start redis-server
    #redis-cli -s /var/run/redis/redis-server.sock flushall
    systemctl start fail2ban
    systemctl start $php-fpm
    systemctl start mariadb
    systemctl start nginx
    systemctl start cron
fi
