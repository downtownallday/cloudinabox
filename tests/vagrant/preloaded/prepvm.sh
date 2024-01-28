#!/bin/bash

# Run this on a VM to pre-install all the packages, then
# take a snapshot - it will greatly speed up subsequent
# test installs

if [ ! -d "setup" ]; then
    echo "Run from the ciab root directory"
    exit 1
fi

# add our key to vagrant authorized_keys
vagrant_home="$(getent passwd vagrant | awk -F: '{print $6}')"
cat $(dirname $0)/keys/*.pub >> $vagrant_home/.ssh/authorized_keys || exit 1

# apt upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get --with-new-pkgs upgrade -y
apt-get autoremove -y

# extra packages
snap install --classic emacs
apt-get install -y -qq ntpdate net-tools jq

# remove apache, which is what setup will do
apt-get -y -qq purge apache2 apache2-\*

echo ""
echo ""
echo "Done. Take a snapshot...."
echo ""
