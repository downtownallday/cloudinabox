
if [ -s /etc/cloudinabox.conf ]; then
    source /etc/cloudinabox.conf
    [ $? -eq 0 ] || exit 1
else
    STORAGE_ROOT="/home/${STORAGE_USER:-user-data}"
fi

EHDD_IMG="${EHDD_IMG:-$STORAGE_ROOT.HDD}"
EHDD_MOUNTPOINT="${EHDD_MOUNTPOINT:-$STORAGE_ROOT}"
EHDD_LUKS_NAME="${EHDD_LUKS_NAME:-c1}"


find_unused_loop() {
    losetup -f
}

find_inuse_loop() {
    losetup -l | awk "\$6 == \"$EHDD_IMG\" { print \$1 }"
}

keyfile_option() {
    if [ ! -z "$EHDD_KEYFILE" ]; then
        echo "--key-file $EHDD_KEYFILE"
    fi
}

system_installed_with_encryption_at_rest() {
    # must be mounted!
    if [ -e "$EHDD_IMG" -a ! -z "$STORAGE_ROOT" -a \
            -e "$STORAGE_ROOT/ssl/ssl_private_key.pem" ]; then
        return 0
    fi
    return 1
}
