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

source_miab_script "setup/system-miab-mods.sh"

# turn off "info" messages from systemd
systemd-analyze set-log-level notice

# Encryption-at-rest disables certain services after setup runs (see
# ehdd/postinstall.sh) because the STORAGE_ROOT directory won't be
# mounted after a reboot and those services would fail. This causes a
# problem if one of those services is upgraded by unattended-upgrades.
#
# The issue: when the system is running normally and
# unattended-upgrades updates a disabled (but running) service
# (eg. mariadb), the service is stopped for the upgrade but is
# never re-started.
#
# The fix: have systemd watch unattended-upgrades, then start all
# services that were upgraded and disabled after updates have been
# applied.

cp conf/ehdd-unattended-upgrades-after.path \
   conf/ehdd-unattended-upgrades-after.service \
   /etc/systemd/system \
    || die "Could not install files in /etc/systemd/system"

tools/editconf.py \
     /etc/systemd/system/ehdd-unattended-upgrades-after.service \
    -ini-section Service \
    "WorkingDirectory=$(pwd)" \
    "ExecStart=$(pwd)/ehdd/startup.sh --no-mount"

systemctl daemon-reload
systemctl enable -q ehdd-unattended-upgrades-after.path || die
systemctl start -q ehdd-unattended-upgrades-after.path || die
