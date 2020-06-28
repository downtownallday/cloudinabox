#!/bin/bash
# This script is run daily (at 3am each night).

# Set character encoding flags to ensure that any non-ASCII
# characters don't cause problems. See setup/start.sh and
# the management daemon startup script.
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_TYPE=en_US.UTF-8

email() {
  local subject="$1"
  management/email_administrator.sh "$subject" 2>&1 | /usr/bin/logger -t CLOUDINABOX
}

# Take a backup.
python3 management/backup.py | email "Backup Status"

# Provision any new certificates for new domains or domains with expiring certificates.
python3 management/ssl_certificates.py -q | email "TLS Certificate Provisioning Result"

# Run status checks and email the administrator if anything changed.
python3 management/status_checks.py --show-changes | email "Status Checks Change Notice"
