#!/bin/bash

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "preloaded-ubuntu-noble" "/cloudinabox" || exit 1

# Setup system
provision_shell <<<"
cd /cloudinabox
export PRIMARY_HOSTNAME='${inst}-ciab.local'
export EHDD_KEYFILE='/root/keyfile'
echo -n 'boo' > \$EHDD_KEYFILE
tests/system-setup/vanilla.sh -v || exit 1
tests/runner.sh default || exit 2
"

provision_done $?

