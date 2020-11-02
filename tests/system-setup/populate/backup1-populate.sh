#!/bin/bash

# restore backup 1
#
# backup1 has a user named "qauser" with file "test.txt" with the contents
# "Hello", and the "Deck" app installed and enabled
#
# the ssl certificate has a common name of "qacloud.int.com"
#

duplicity_files=tests/assets/backup/backup1/encrypted
secret_key=tests/assets/backup/backup1/secret_key.txt
restore_to=${1:-$STORAGE_ROOT}

tests/bin/restore_backup.sh "$duplicity_files" "$secret_key" "$restore_to"

