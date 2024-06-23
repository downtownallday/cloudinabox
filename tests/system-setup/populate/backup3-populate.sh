#!/bin/bash

# restore backup 3
#
# backup3 has a user named "qauser" (password "qauser_test_1234") with
# file "test.txt" with the contents "Hello", and the "Deck" app
# installed and enabled
#
# nextcloud is version 29 (requires PHP 8.1, PHP 8.2, or PHP 8.3)
#
# the ssl certificate has a common name of "qacloud.int.com" and
# expires Jun 22 16:27:55 2025 GMT
#

duplicity_files=tests/assets/backup/backup3/encrypted
secret_key=tests/assets/backup/backup3/secret_key.txt
restore_to=${1:-$STORAGE_ROOT}

tests/bin/restore_backup.sh "$STORAGE_USER" "$duplicity_files" "$secret_key" "$restore_to"

# remove the certificate, it might not be valid and will be
# regenerated during setup
rm "$STORAGE_ROOT/ssl/ssl_certificate.pem"
