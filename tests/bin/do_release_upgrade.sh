#!/bin/bash

# upgrade the OS without interaction
# must be run by root

echo ""
echo "RELEASE UPGRADE UBUNTU - LTS"
echo "Current: $(. /etc/os-release; echo $VERSION)"

$(dirname "$0")/../../tools/editconf.py \
              /etc/update-manager/release-upgrades \
              -ini-section DEFAULT \
              Prompt=${1:-lts} \
              || exit 1

apt-get update || exit 1
apt-get --with-new-pkgs upgrade -y || exit 1
# might require a reboot here

# silent install (DistUpgradeViewNonInteractive) does not work, need
# input redirection...
idx=0
tmp="$(mktemp)"
while [ $idx -lt 40 ]; do
    echo "" >> $tmp
    let idx+=1
done

echo ""
echo "STARTING DO-RELEASE-UPGRADE"
echo ""
/usr/bin/do-release-upgrade -f DistUpgradeViewNonInteractive <$tmp
code=$?

rm -f $tmp

if [ $code -eq 0 ]; then
    echo ""
    echo "RELEASE UPGRADE SUCCEEDED!"
    echo "Current: $(. /etc/os-release; echo $VERSION)"
    exit 0
else
    echo "RELEASE UPGRADE FAILED WITH EXIT CODE $code"
    exit 1
fi
