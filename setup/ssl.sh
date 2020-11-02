#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

# use mail-in-a-box's ssl setup script...
source_miab_script "setup/ssl-miab.sh"

