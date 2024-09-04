#!/bin/bash

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "" "/cloudinabox" || exit 1
#provision_start "preloaded-ubuntu-jammy" "/cloudinabox" || exit 1

# Setup system
if [ "$1" = "miab" ]; then
    # vanilla connected to remote miab (miab-ldap with hostname
    # "vanilla.local" must be up and running)
    provision_shell <<<"
cd /cloudinabox
export PRIMARY_HOSTNAME='${inst}-ciab.local'
export MAILINABOX_HOST=vanilla.local
export MAILINABOX_SERVICE_PASSWORD=Test_LDAP_1234
export MAILINABOX_SMARTHOST_AUTH_USER=qa@abc.com
export MAILINABOX_SMARTHOST_AUTH_PASSWORD=Test_1234
tests/system-setup/vanilla.sh -v
"
    provision_done $?
    
else
    # vanilla (default - no miab integration)
    provision_shell <<<"
cd /cloudinabox
export PRIMARY_HOSTNAME='${inst}-ciab.local'
tests/system-setup/vanilla.sh -v
"
    provision_done $?

fi
