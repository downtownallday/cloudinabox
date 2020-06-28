#!/bin/bash

. setup/functions.sh     || exit 1
. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"

# use mail-in-a-box's ssl setup script...
source_miab_script "setup/ssl-miab.sh"

