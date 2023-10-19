#!/bin/bash

# Run this on a VM to pre-install all the packages, then
# take a snapshot - it will greatly speed up subsequent
# test installs


if [ ! -d "setup" ]; then
    echo "Run from the ciab root directory"
    exit 1
fi

dry_run=false

. /etc/os-release
OS_MAJOR=$(awk -F. '{print $1}' <<<"$VERSION_ID")

export DEBIAN_FRONTEND=noninteractive



if ! $dry_run; then
    apt-get update -y
    apt-get --with-new-pkgs upgrade -y
    apt-get autoremove -y

    # bonus
    if [ $OS_MAJOR -le 18 ]; then
        apt-get install -y -qq emacs-nox
    else
        snap install --classic emacs
    fi
    apt-get install -y -qq ntpdate net-tools jq

    # remove apache, which is what setup will do
    apt-get -y -qq purge apache2 apache2-\*

    echo ""
    echo ""
    echo "Done. Take a snapshot...."
    echo ""
fi
