#!/bin/bash

#
# restore from backup
#

# ensure working directory
if [ ! -d "tests/system-setup" ]; then
    echo "This script must be run from the MiaB root directory"
    exit 1
fi

# load helper scripts
. "tests/lib/all.sh" "tests/lib" || die "Could not load lib scripts"
. "tests/system-setup/setup-defaults.sh" || die "Could not load setup-defaults"
. "tests/system-setup/setup-funcs.sh" || die "Could not load setup-funcs"

# ensure running as root
if [ "$EUID" != "0" ]; then
    die "This script must be run as root (sudo)"
fi


init() {
    H1 "INIT"
    init_test_system
    init_ciab_testing "$@" || die "Initialization failed"
}


# initialize test system
init "$@"

# restore data
populate_by_name "${1:-backup1}"

# run setup
ciab_install
