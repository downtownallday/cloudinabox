#!/bin/bash

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "preloaded-ubuntu-noble" "/cloudinabox" || exit 1

# Setup system
provision_shell <<<"
cd /cloudinabox
export PRIMARY_HOSTNAME='qacloud.int.com'
tests/system-setup/from-backup.sh backup3 || exit 1
tests/runner.sh default upgrade-backup3 || exit 2
"

provision_done $?
