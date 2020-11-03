
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
    if is_false "$TRAVIS" && [ "$SKIP_SYSTEM_UPDATE" != "1" ]; then
        H2 "apt-get upgrade"
        wait_for_apt
        apt-get --with-new-pkgs -y upgrade || die "apt-get upgrade failed!"
    fi

    # install avahi if the system dns domain is .local - note that
    # /bin/dnsdomainname returns empty string at this point
    case "$PRIMARY_HOSTNAME" in
        *.local )
            wait_for_apt
            apt-get install -y -qq avahi-daemon || die "could not install avahi"
            ;;
    esac
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
        
    # process command line args
    while [ $# -gt 0 ]; do
        case "$1" in
            --qa-ca )
                echo "Copy certificate authority"
                shift
                if ! cp tests/assets/ssl/ca_*.pem $STORAGE_ROOT/ssl; then
                    echo "Copy failed ($?)"
                    rc=1
                fi
                ;;

            --enable-mod=* )
                local mod="$(awk -F= '{print $2}' <<<"$1")"
                shift
                echo "Enabling local mod '$mod'"
                if ! enable_ciab_mod "$mod"; then
                    echo "Enabling mod '$mod' failed"
                    rc=1
                fi
                ;;

            * )
                # ignore unknown option - may be interpreted elsewhere
                shift
                ;;
        esac            
    done
    
    # now that we've copied our files, unmount STORAGE_ROOT if
    # encryption-at-rest was enabled
    ehdd/umount.sh
    
    return $rc
}

enable_ciab_mod() {
    local name="${1}.sh"
    if [ ! -e "$LOCAL_MODS_DIR/$name" ]; then
        mkdir -p "$LOCAL_MODS_DIR"
        if ! ln -s "$(pwd)/setup/mods.available/$name" "$LOCAL_MODS_DIR/$name"
        then
            echo "Warning: copying instead of symlinking $LOCAL_MODS_DIR/$name"
            cp "setup/mods.available/$name" "$LOCAL_MODS_DIR/$name"
        fi
    fi
}

disable_ciab_mod() {
    local name="${1}.sh"
    rm -f "$LOCAL_MODS_DIR/$name"
}


ciab_install() {
    H1 "CIAB INSTALL"

    # process command line args
    local start_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -v )
                start_args+=("$1")
                shift
                ;;
            * )
                # ignore unknown option - may be interpreted elsewhere
                shift
                ;;
        esac
    done

    # if EHDD_KEYFILE is set, use encryption-at-rest support
    if [ ! -z "$EHDD_KEYFILE" ]; then
        ehdd/start-encrypted.sh ${start_args[@]}
    else
        setup/start.sh ${start_args[@]}
    fi
    
    if [ $? -ne 0 ]; then
        H1 "OUTPUT OF SELECT FILES"
        dump_file "/var/log/syslog" 100
        dump_file_if_exists "/var/log/redis/redis-server.log" 20
        dump_file_if_exists "/var/log/mysql/error.log" 20
        dump_nextcloud_log "/var/log/nextcloud/nextcloud.log" 10
        H2; H2 "End"; H2
        die "Setup failed!"
    fi

    # set actual STORAGE_ROOT, STORAGE_USER, PRIVATE_IP, etc
    . /etc/cloudinabox.conf || die "Could not source /etc/cloudinabox.conf"

    # setup changes the hostname so avahi must be restarted
    if systemctl is-active --quiet avahi-daemon; then
        systemctl restart avahi-daemon
    fi
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


dump_nextcloud_log() {
    local log_file="$1"
    local lines="$2"
    local title="DUMP OF $log_file"
    echo ""
    echo "--------"
    echo -n "-------- $log_file"
    if [ ! -z "$lines" ]; then
        echo " (last $line lines)"
    else
        echo ""
    fi
    echo "--------"

    local jq="/usr/bin/jq -c '{t:.time,a:.app?,m:.message}'"
    if [ ! -x /usr/bin/jq ]; then
        jq="cat"
    fi

    if [ ! -e "$log_file" ]; then
        echo "DOES NOT EXIST"
    elif [ ! -z "$lines" ]; then
        tail -$lines "$log_file" | $jq
    else
        cat "$log_file" | $jq
    fi
}
