#
# requires:
#    scripts: [ colored-output.sh, rest.sh ]
#
# these functions are meant for comparing upstream (non-LDAP)
# installations to a subsequent MiaB-LDAP upgrade
#


installed_state_capture() {
    # users and aliases
    # dns zone files
    # TOOD: tls certificates: expected CN's

    local state_dir="$1"
    local info="$state_dir/info.txt"

    H1 "Capture installed state to $state_dir"

    # nuke saved state, if any
    rm -rf "$state_dir"
    mkdir -p "$state_dir"

    # create info.json
    H2 "create info.txt"
    echo "STATE_VERSION=1" > "$info"
    echo "GIT_VERSION='$(git describe --abbrev=0)'" >>"$info"
    echo "MIGRATION_VERSION=$(cat "$STORAGE_ROOT/mailinabox.version")" >>"$info"

    # record users
    H2 "record users"
    if ! rest_urlencoded GET "/admin/mail/users?format=json" "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null
    then
        echo "Unable to get users: rc=$? err=$REST_ERROR" 1>&2
        return 1
    fi
    echo "$REST_OUTPUT" > "$state_dir/users.json"

    # record aliases
    H2 "record aliases"
    if ! rest_urlencoded GET "/admin/mail/aliases?format=json" "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null
    then
        echo "Unable to get aliases: rc=$? err=$REST_ERROR" 1>&2
        return 2
    fi
    echo "$REST_OUTPUT" > "$state_dir/aliases.json"

    # record dns config
    H2 "record dns details"
    local file
    mkdir -p "$state_dir/zones"
    for file in /etc/nsd/zones/*.signed; do
        if ! cp "$file" "$state_dir/zones"
        then
            echo "Copy $file -> $state_dir/zones failed" 1>&2
            return 3
        fi
    done
    
    return 0
}



installed_state_compare() {
    local s1="$1"
    local s2="$2"
    
    local output
    local changed="false"

    H1 "COMPARE STATES: $(basename "$s1") VS $(basename "$2")"
    H2 "Users"
    # users
    output="$(diff "$s1/users.json" "$s2/users.json" 2>&1)"
    if [ $? -ne 0 ]; then
        changed="true"
        echo "USERS ARE DIFFERENT!"
        echo "$output"
    else
        echo "No change"
    fi

    H2 "Aliases"
    output="$(diff "$s1/aliases.json" "$s2/aliases.json" 2>&1)"
    if [ $? -ne 0 ]; then
        change="true"
        echo "ALIASES ARE DIFFERENT!"
        echo "$output"
    else
        echo "No change"
    fi

    H2 "DNS - zones missing"
    local zone count=0
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "MISSING zone: $zone"
            changed="true"
            let count+=1
        fi
    done
    echo "$count missing"

    H2 "DNS - zones added"
    count=0
    for zone in $(cd "$s2/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "ADDED zone: $zone"
            changed="true"
            let count+=1
        fi
    done
    echo "$count added"

    H2 "DNS - zones changed"
    count=0
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ -e "$s2/zones/$zone" ]; then
            # all the signatures change if we're using self-signed certs
            local t1="/tmp/s1.$$.txt"
            local t2="/tmp/s2.$$.txt"
            awk '$4 == "RRSIG" || $4 == "NSEC3" { next; } $4 == "SOA" { print $1" "$2" "$3" "$4" "$5" "$6" "$8" "$9" "$10" "$11" "$12; next } { print $0 }' "$s1/zones/$zone" > "$t1" 
            awk '$4 == "RRSIG" || $4 == "NSEC3" { next; } $4 == "SOA" { print $1" "$2" "$3" "$4" "$5" "$6" "$8" "$9" "$10" "$11" "$12; next } { print $0 }' "$s2/zones/$zone" > "$t2" 
            output="$(diff "$t1" "$t2" 2>&1)"
            if [ $? -ne 0 ]; then
                echo "CHANGED zone: $zone"
                echo "$output"
                changed="true"
                let count+=1
            fi
        fi
    done
    echo "$count zone files had differences"

    if $changed; then
        return 1
    else
        return 0
    fi
}
