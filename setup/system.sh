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

# remove ondrej ppa if it's already installed
if add-apt-repository -L | grep -q ondrej/php; then
	if systemctl is-active --quiet nginx; then
		systemctl stop nginx
	fi
	for v in $(ls /usr/bin/php[0-9]*.[0-9]*); do
		if ! $v --version | grep -qi ubuntu; then
			v=$(basename $v)
			echo "Removing ondrej/php $v"
			pkgs=$(dpkg -l | awk "/^.i/ && index(\$2,\"$v\")>0 {print \$2}")
			wait_for_apt_lock
			hide_output apt-get purge -y $pkgs
		fi
	done
	hide_output add-apt-repository --remove ppa:ondrej/php
fi

# make sure we don't reinstall ppa:ondrej/php
sed -i 's/^\(hide_output add-apt-repository --y ppa:ondrej\/php\)$/#\1/g' setup/system-miab-mods.sh

source_miab_script "setup/system-miab-mods.sh"

# turn off "info" messages from systemd
systemd-analyze set-log-level notice
