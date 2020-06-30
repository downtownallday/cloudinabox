#!/bin/bash

. /etc/cloudinabox.conf || exit 1

occ="${NEXTCLOUD_PATH:-/usr/local/nextcloud}/occ"

# 'qauser' exists
echo "[qauser exists]" 1>&2
if ! sudo -E -u www-data php "$occ" user:list | grep -F "qauser: " >/dev/null; then
    echo "qauser does not exist!"
    exit 1
fi


# test.txt exists and contains 'Hello'
echo "[test file exists and has expected content]" 1>&2
hello=$(cat $STORAGE_ROOT/nextcloud/data/qauser/files/test.txt | sed 's/ *$//')
if [ $? -ne 0 ]; then
    echo "Test file does not exist!"
    exit 1
fi
if [ "$hello" != "Hello" ]; then
    echo "Unexpected test file contents: '$hello' vs 'Hello'"
    exit 1
fi

exit 0
