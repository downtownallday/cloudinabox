#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1

if [ -e "$EHDD_IMG" ]; then
    
    if [ -s /etc/cloudinabox.conf ]; then
        echo ""
        echo "** Disabling system services **"
        systemctl disable nginx
        systemctl disable mariadb
        systemctl disable redis-server
        systemctl disable cron
        systemctl disable fail2ban

        echo ""
        echo "IMPORTANT:"
        echo "    Services have been disabled at startup because the encrypted HDD will"
        echo "    be unavailable. Run ehdd/startup.sh after a reboot."
    fi

fi

