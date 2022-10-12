#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1

if [ -e "$EHDD_IMG" ]; then
    
    if [ -s /etc/cloudinabox.conf ]; then
        echo ""
        echo "** Disabling system services **"
        systemctl disable --quiet nginx
        systemctl disable --quiet mariadb
        systemctl disable --quiet redis-server
        systemctl disable --quiet cron
        systemctl disable --quiet fail2ban

        echo ""
        echo "IMPORTANT:"
        echo "    Services have been disabled at startup because the encrypted HDD will"
        echo "    be unavailable. Run ehdd/startup.sh after a reboot."
    fi

fi

