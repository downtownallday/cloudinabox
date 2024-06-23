#!/bin/bash

. /etc/cloudinabox.conf || exit 1

occ="${NEXTCLOUD_PATH:-/usr/local/nextcloud}/occ"
php=$(cd $CIAB_DIR; . setup/functions.sh; get_required_php_version; echo $REQUIRED_PHP_EXECUTABLE)

# 'qauser' exists
echo "[qauser exists]" 1>&2
if ! sudo -E -u www-data $php "$occ" user:list | grep -F "qauser: " >/dev/null; then
    echo "qauser does not exist!"
    exit 1
fi
echo "true" 1>&2


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
echo "true" 1>&2


# Deck app is installed and enabled
echo "[Deck app is installed and enabled]" 1>&2
isenabled=$(sudo -E -u www-data $php "$occ" app:list | python3 -c "import yaml,sys; print('true' if 'deck' in [ list(item)[0] for item in yaml.load(sys.stdin, yaml.CLoader)['Enabled']] else 'false')")

if [ $? -ne 0 ]; then
    echo "Could not list installed Nextcloud apps!"
    exit 1
fi

if [ "$isenabled" != "true" ]; then
    echo "Problem - the Deck app is not installed or not enabled (result=$isenabled)"
    exit 1
else
    echo "$isenabled" 1>&2
fi


exit 0
