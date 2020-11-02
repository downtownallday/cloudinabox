
# load useful functions from setup
. /etc/cloudinabox.conf || die "Could not load '/etc/cloudinabox.conf'"

pushd .. >/dev/null
. setup/functions.sh || exit 1
popd >/dev/null

# TODO: load test suite helper functions

CIAB_DIR=".."


#
# load vars produced during installation
#

. "${CIAB_SQL_CONF}" || die "Could not load '${CIAB_SQL_CONF}'"
. "${CIAB_NEXTCLOUD_CONF}" || die "Could not load '${CIAB_NEXTCLOUD_CONF}'"
