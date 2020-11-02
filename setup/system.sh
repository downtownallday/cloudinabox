#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

# use mail-in-a-box's system.sh, but we don't want the following
# packages beacuse they install build-essentials, which is large, and
# we don't need it.
#    - python3-dev
#    - python3-pip
#
# we do require these additional packages:
#    + python3-dateutil
#    + python3-dnspython
#    + python3-psutil
#    + xz-utils
#    + jq
#

echo "# GENERATED FILE - DO NOT EDIT - GENERATED FROM setup/system-miab.sh" > setup/system-miab-mods.sh \
     || die "Could not create setup/system-miab-mods.sh"

cat setup/system-miab.sh >> setup/system-miab-mods.sh \
    || die "Could not copy setup/system-miab.sh"

sed -i "s/python3-dev/python3-dateutil/g" setup/system-miab-mods.sh \
    || die "Could not edit setup/system-miab-mods.sh"

sed -i "s/python3-pip/python3-dnspython python3-psutil xz-utils jq/g" setup/system-miab-mods.sh \
    || die "Could not edit setup/system-miab-mods.sh"

if [ $OS_MAJOR -gt 18 -a ! -e /etc/default/bind9 ]; then
    # in ubuntu 20:
    #    /etc/default/bind9 change to /etc/default/named
    # create a symlink so editconf succeeds
    ln -s named /etc/default/bind9
fi

source_miab_script "setup/system-miab-mods.sh"

# turn off "info" messages from systemd
systemd-analyze set-log-level notice
