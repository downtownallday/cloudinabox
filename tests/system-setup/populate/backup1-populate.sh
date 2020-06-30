#!/bin/bash

# restore backup 1
#
# backup1 has a user named "qauser" with file "test.txt" with the contents
# "Hello"
#

duplicity_files=tests/assets/backup/backup1/encrypted
secret_key=tests/assets/backup/backup1/secret_key.txt
restore_to=${1:-/home/user-data}

tests/lib/restore_backup.sh "$duplicity_files" "$secret_key" "$restore_to"

