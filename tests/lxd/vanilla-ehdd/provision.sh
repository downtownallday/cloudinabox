#!/bin/bash

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "preloaded-ubuntu-noble" "/cloudinabox" || exit 1

# Setup system
lxc --project "$project" exec "$inst" \
    --cwd /cloudinabox \
    --env PRIMARY_HOSTNAME="${inst}-ciab.local" \
    --env EHDD_KEYFILE="/root/keyfile" \
    -- \
    /bin/bash -c "
echo -n 'boo' > \$EHDD_KEYFILE &&
tests/system-setup/vanilla.sh -v &&
tests/runner.sh default
"

provision_done $?

