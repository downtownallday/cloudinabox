#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1

if system_installed_with_encryption_at_rest; then    
    echo ""
    echo "** Disabling system services that require encrypted HDD to be mounted **"
    systemctl disable --quiet nginx
    systemctl disable --quiet mariadb
    systemctl disable --quiet redis-server
    systemctl disable --quiet cron
    systemctl disable --quiet fail2ban
    
    echo ""
    echo "IMPORTANT:"
    echo "    Services have been disabled at startup because the encrypted HDD will"
    echo "    be unavailable. Run ehdd/run-this-after-reboot.sh after a reboot."
fi
