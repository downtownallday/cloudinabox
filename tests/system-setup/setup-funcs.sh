
#
# requires:
#
#   test scripts: [ lib/misc.sh, lib/system.sh ]
#


die() {
    local msg="$1"
    echo "$msg" 1>&2
    exit 1
}

#
# Initialize the test system
#   hostname, time, apt update/upgrade, etc
#
# Errors are fatal
#
init_test_system() {
    H2 "Update /etc/hosts"
    set_system_hostname || die "Could not set hostname"

    # update system time
    H2 "Set system time"
    update_system_time || echo "Ignoring error..."
    
    # update package lists before installing anything
    H2 "apt-get update"
    wait_for_apt
    apt-get update -qq || die "apt-get update failed!"

    # upgrade packages - if we don't do this and something like bind
    # is upgraded through automatic upgrades (because maybe MiaB was
    # previously installed), it may cause problems with the rest of
    # the setup, such as with name resolution failures
    if is_false "$TRAVIS"; then
        H2 "apt-get upgrade"
        wait_for_apt
        apt-get upgrade -qq || die "apt-get upgrade failed!"
    fi
}


#
# Initialize the test system with QA prerequisites
# Anything needed to use the test runner, speed up the installation,
# etc
#
init_ciab_testing() {
    [ -z "$STORAGE_ROOT" ] \
        && echo "Error: STORAGE_ROOT not set" 1>&2 \
        && return 1

    # If EHDD_KEYFILE is set, use encryption-at-rest support.  The
    # drive must be created and mounted so that our QA files can be
    # copied there.
    H2 "Encryption-at-rest"
    if [ ! -z "$EHDD_KEYFILE" ]; then
        ehdd/create_hdd.sh ${EHDD_GB} || die "create luks drive failed"
        ehdd/mount.sh || die "unable to mount luks drive"
    else
        echo "Not configured for encryption-at-rest"
    fi
    
    H2 "QA prerequisites"
    local rc=0
        
    # copy in pre-built ssl files
    #   1. avoid the lengthy generation of DH params
    if ! mkdir -p $STORAGE_ROOT/ssl; then
        echo "Unable to create $STORAGE_ROOT/ssl ($?)"
        rc=1
    fi

    echo "Copy dhparams"
    if ! cp tests/assets/ssl/dh2048.pem $STORAGE_ROOT/ssl; then
        echo "Copy dhparams failed ($?)"
        rc=1
    fi
        
    if array_contains "--qa-ca" "$@"; then
        echo "Copy certificate authority"
        if ! cp tests/assets/ssl/ca_*.pem $STORAGE_ROOT/ssl; then
            echo "Copy failed ($?)"
            rc=1
        fi
    fi
    
    # now that we've copied our files, unmount STORAGE_ROOT if
    # encryption-at-rest was enabled
    ehdd/umount.sh
    
    return $rc
}


ciab_install() {
    H1 "CIAB INSTALL"

    # if EHDD_KEYFILE is set, use encryption-at-rest support
    if [ ! -z "$EHDD_KEYFILE" ]; then
        ehdd/start-encrypted.sh
    else
        setup/start.sh
    fi
    
    if [ $? -ne 0 ]; then
        H1 "OUTPUT OF SELECT FILES"
        dump_file "/var/log/syslog" 100
        H2; H2 "End"; H2
        die "Setup failed!"
    fi

    # set actual STORAGE_ROOT, STORAGE_USER, PRIVATE_IP, etc
    . /etc/cloudinabox.conf || die "Could not source /etc/cloudinabox.conf"
}


populate_by_name() {
    local populate_name="$1"

    H1 "Populate Cloud-in-a-Box ($populate_name)"
    local populate_script="tests/system-setup/populate/${populate_name}-populate.sh"
    if [ ! -e "$populate_script" ]; then
        die "Does not exist: $populate_script"
    fi
    "$populate_script" || die "Failed: $populate_script"
}
