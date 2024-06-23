#!/bin/bash

# Run this on a VM to pre-install all the packages, then take a
# snapshot - it will speed up subsequent test installs

if [ ! -d "setup" ]; then
    echo "Run from the ciab root directory"
    exit 1
fi
    
cat <<EOF > /etc/ssh/sshd_config.d/05-prepvm.conf
# created by tests/../preloaded/prepvm.sh
PidFile /run/sshd.pid
PasswordAuthentication no
EOF
systemctl enable ssh

# apt upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get --with-new-pkgs upgrade -y
apt-get autoremove -y

# extra packages
snap install --classic emacs
apt-get install -y -qq ntpdate net-tools jq lbzip2

# remove apache, which is what setup will do
apt-get -y -qq purge apache2 apache2-\*

echo ""
echo ""
echo "Done. Take a snapshot...."
echo ""
