#!/bin/bash

#
# setup a vanilla system but use encryption-at-rest
#

export EHDD_KEYFILE="$HOME/keyfile"
export EHDD_GB=2

echo -n "boo" > "$EHDD_KEYFILE"
$(dirname "$0")/vanilla.sh "$@"
