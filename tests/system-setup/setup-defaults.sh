#!/bin/bash

# Used by setup/start.sh
export PRIMARY_HOSTNAME=${PRIMARY_HOSTNAME:-$(hostname --fqdn || hostname)}
export NONINTERACTIVE=${NONINTERACTIVE:-1}
export SKIP_SYSTEM_UPDATE=${SKIP_SYSTEM_UPDATE:-1}
export STORAGE_USER="${STORAGE_USER:-user-data}"
export STORAGE_ROOT="${STORAGE_ROOT:-/home/$STORAGE_USER}"
export PUBLIC_IP="${PUBLIC_IP:-$(source ${MIAB_DIR:-.}/setup/functions.sh; get_default_privateip 4)}"
export ALERTS_EMAIL="${ALERTS_EMAIL:-qa@abc.com}"
export LOCAL_MODS_DIR="${LOCAL_MODS_DIR:-local}"
export DOWNLOAD_CACHE_DIR="${DOWNLOAD_CACHE_DIR:-$(pwd)/downloads}"
export DOWNLOAD_NEXTCLOUD_FROM_GITHUB="${DOWNLOAD_NEXTCLOUD_FROM_GITHUB:-false}"

# Used by ehdd/start-encrypted.sh
export EHDD_KEYFILE="${EHDD_KEYFILE:-}"
export EHDD_GB="${EHDD_GB:-2}"

# For integrating with MiaB-LDAP
export MAILINABOX_HOST="${MAILINABOX_HOST}"
export MAILINABOX_SERVICE_PASSWORD="${MAILINABOX_SERVICE_PASSWORD:-Test_LDAP_1234}"
export MAILINABOX_SMARTHOST_AUTH_USER="${MAILINABOX_SMARTHOST_AUTH_USER:-qa@abc.com}"
export MAILINABOX_SMARTHOST_AUTH_PASSWORD="${MAILINABOX_SMARTHOST_AUTH_PASSWORD:-Test_1234}"

