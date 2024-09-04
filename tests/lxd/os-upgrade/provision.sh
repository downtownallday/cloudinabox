#!/bin/bash

D=$(dirname "$BASH_SOURCE")
. "$D/../../lib/color-output.sh" || exit 1
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance of a base OS that will be upgraded
provision_start "preloaded-ubuntu-jammy" "/cloudinabox" || exit 1

# Setup system
lxc --project "$project" exec "$inst" \
    --cwd /cloudinabox \
    --env PRIMARY_HOSTNAME="os-upgrade.abc.com" \
    --env SKIP_SYSTEM_UPDATE=0 \
    -- \
    /bin/bash -c "
tests/system-setup/vanilla.sh -v &&
tests/runner.sh default
"

# a reboot may be required when updates were applied
if lxc --project "$project" exec "$inst" -- /bin/bash -c "[ -e /var/run/reboot-required ]"; then
    warn "A reboot is required - rebooting now"
    lxc --project "$project" restart "$inst" || exit 1
    lx_wait_for_boot "$project" "$inst" || exit 1
fi

# upgrade ubuntu
lxc --project "$project" exec "$inst" \
    --cwd /cloudinabox \
    -- \
    "tests/bin/do_release_upgrade.sh" \
    || exit 2


# a reboot is required after any system upgrade
warn "A reboot is required after any system upgrade - rebooting now"
lxc --project "$project" restart "$inst" || exit 2
lx_wait_for_boot "$project" "$inst" || exit 2

# re-run setup, then run test suites
lxc --project "$project" exec "$inst" \
    --cwd /cloudinabox \
    -- \
    /bin/bash -c "
source tests/system-setup/setup-defaults.sh &&
setup/start.sh -v &&
tests/runner.sh default
" \
    || exit 3


provision_done $?
