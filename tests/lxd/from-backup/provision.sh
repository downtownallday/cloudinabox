#!/bin/bash

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "preloaded-ubuntu-noble" "/cloudinabox" || exit 1

# Setup system
lxc --project "$project" exec "$inst" \
    --cwd /cloudinabox \
    --env PRIMARY_HOSTNAME="qacloud.int.com" \
    -- \
    /bin/bash -c "
tests/system-setup/from-backup.sh backup3 &&
tests/runner.sh default upgrade-backup3
"

provision_done $?
