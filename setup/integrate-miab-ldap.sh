
. setup/functions.sh     || exit 1
. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. $STORAGE_ROOT/nextcloud/ciab_nextcloud.conf || die "Could not load $STORAGE_ROOT/nextcloud/ciab_nextcloud.conf"


NCDIR=/usr/local/nextcloud
CONF="$STORAGE_ROOT/integrations.conf"

if [ ! -e "$CONF" ]; then
    mkdir -p "$(dirname "$CONF")"
    touch "$CONF" || die "Could not touch $CONF"
    chmod 640 "$CONF" || die "Could not change permissions of $CONF"
fi

# load previous values only if running interactively
if [ -z "$NONINTERACTIVE" ]; then
    . "$CONF" || die "Could not load $CONF"
fi



read_host() {
    local ans="" ans_host
    echo ""
    echo "What is the fully-qualified hostname of your MiaB-LDAP server?"
    if [ -z "$MAILINABOX_HOST" ]; then
        read -p "[<not currently set>] " ans_host
    else
        read -p "[$MAILINABOX_HOST] " ans_host
    fi
    MAILINABOX_HOST="${ans_host:-$MAILINABOX_HOST}"
}

read_service_password() {
    local ans_service_pw
    echo ""
    echo "Enter the password Nextcloud will use for LDAP access"
    echo "** Obtain the password from your MiaB-LDAP server in /home/user-data/ldap/miab_ldap.conf, look for key \"LDAP_NEXTCLOUD_PASSWORD\" and paste the value here **"
    if [ -z "$MAILINABOX_SERVICE_PASSWORD" ]; then
        read -s -p "[<not currently set>] " ans_service_pw
        echo ""
    else
        read -s -p "[leave blank to keep the existing setting] " ans_service_pw
        if [ ! -z "$ans_service_pw" ]; then
            # strip leading and trailing double quotes
            ans_service_pw="${ans_service_pw%\"}"
            ans_service_pw="${ans_service_pw#\"}"
        fi
        echo ""
    fi
    MAILINABOX_SERVICE_PASSWORD="${ans_service_pw:-$MAILINABOX_SERVICE_PASSWORD}"
}

read_smarthost_auth() {
    local ans_smarthost_user ans_smarthost_pw
    echo ""
    echo "Use MiaB as a mail \"smart host\""
    echo "** This server must authenticate with MiaB to be able to send mail. Enter the email address this server will authenticate as. It must be a user account you created in Mail-in-a-Box **"
    if [ -z "$MAILINABOX_SMARTHOST_AUTH_USER" ]; then
        read -p  "[<not currently set>] " ans_smarthost_user
    else
        read -p  "[$MAILINABOX_SMARTHOST_AUTH_USER] " ans_smarthost_user
    fi
    
    if [ -z "$MAILINABOX_SMARTHOST_AUTH_PASSWORD" ]; then
        read -s -p "Password: " ans_smarthost_pw
        echo ""
    else
        read -s -p "Password: [leave blank to keep the existing setting] " ans_smarthost_pw
        echo ""
    fi
    MAILINABOX_SMARTHOST_AUTH_USER="${ans_smarthost_user:-$MAILINABOX_SMARTHOST_AUTH_USER}"
    MAILINABOX_SMARTHOST_AUTH_PASSWORD="${ans_smarthost_pw:-$MAILINABOX_SMARTHOST_AUTH_PASSWORD}"

    echo ""
    echo "IMPORTANT:"
    echo ""
    echo "The smart host user will be sending mail FROM other users, a privilege that must be explicitly granted to $MAILINABOX_SMARTHOST_AUTH_USER. This is accomplished in the Mail-in-a-Box admin interface, by adding a new alias with these settings:"
    echo ""
    echo "    Alias             = @$(hostname --fqdn || hostname)"
    echo "    Forwards to       = <leave this blank>"
    echo "    Permitted-senders = $MAILINABOX_SMARTHOST_AUTH_USER"
    echo ""
    read -n 1 -s -p "Press any key to continue" ans
    echo ""
}


convert_dot_local() {
    case "$MAILINABOX_HOST" in
        *.local )
            # get the ip addr of host.local
            local ip orig="$MAILINABOX_HOST"
            ip=$(getent hosts $MAILINABOX_HOST | awk '{print $1}')
            [ $? -ne 0 ] && return 1
            
            # use this host's domain name and add it to /etc/hosts
            MAILINABOX_HOST="$(awk -F. '{print $1}' <<<"$MAILINABOX_HOST").$(dnsdomainname)"
            echo "Changing \"$orig\" to \"$MAILINABOX_HOST\""

            local entry="$ip $MAILINABOX_HOST"
            if ! grep -F "$entry" /etc/hosts >/dev/null; then
                echo "Adding \"$entry\" to /etc/hosts"
                echo "$entry" >> /etc/hosts
            fi
            ;;
    esac
    return 0
}




save_conf() {
    tools/editconf.py "$CONF" \
                      "MAILINABOX_HOST='$MAILINABOX_HOST'" \
                      "MAILINABOX_SERVICE_PASSWORD='$MAILINABOX_SERVICE_PASSWORD'" \
                      "MAILINABOX_SMARTHOST_AUTH_USER='$MAILINABOX_SMARTHOST_AUTH_USER'" \
                      "MAILINABOX_SMARTHOST_AUTH_PASSWORD='$MAILINABOX_SMARTHOST_AUTH_PASSWORD'" \
        || die "Could not modify $CONF"
}




if [ -z "$NONINTERACTIVE" ]; then
    if [ ! -z "$MAILINABOX_HOST" ]; then
        # once you set it, there is no going back (for now)
        ans="y"
    else
        echo ""
        echo "Integrate Mail-in-a-Box (LDAP) for users and groups"
        echo "---------------------------------------------------"
        echo "Do you want to allow Mail-in-a-Box users to access your Nextcloud?"
        echo "  ** you must have a Mail-in-a-Box with LDAP support already set up **"
        echo ""
        while [ "$ans" != 'n' -a "$ans" != 'N' -a "$ans" != 'y' -a "$ans" != "Y" ]
        do
            read -p "Enable Mail-in-a-Box with LDAP support? [y/n] " -n 1 ans
        done
        echo ""
    fi
    
    if [ "$ans" == 'y' -o "$ans" == 'Y' ]; then
        # read params
        read_host
        read_service_password
        read_smarthost_auth

        # If a host.local name was supplied an ldaps connection will
        # always fail because the server's certificate will not have a
        # common name of host.local. We can at least try to convert it
        # to host.domain.tld, where domain.tld is this hosts's domain
        # name, and add an entry in /etc/hosts for it.
        convert_dot_local

        # save values for next time setup is run
        save_conf

        # execute the integration script that comes with MiaB-LDAP
        export REQUIRED_PHP_VER
        export REQUIRED_PHP_EXECUTABLE
        export REQUIRED_PHP_PACKAGE
        setup/connect-nextcloud-to-miab.sh $NCDIR $NC_ADMIN_USER "$NC_ADMIN_PASSWORD" "$MAILINABOX_HOST" "$MAILINABOX_SERVICE_PASSWORD" "$ALERTS_EMAIL" "$MAILINABOX_SMARTHOST_AUTH_USER" "$MAILINABOX_SMARTHOST_AUTH_PASSWORD"
        rc=$?
        
        # nextcloud admin authentication failed if rc==3
        while [ $rc -eq 3 ]; do
            echo "Authenticating as '$NC_ADMIN_USER' to Nextcloud failed"
            echo "** What is the password for $NC_ADMIN_USER **"
            read -s -p "[$NC_ADMIN_PASSWORD] " ans_nc_admin_pass
            echo ""
            $NC_ADMIN_PASSWORD="${ans_nc_admin_pass:-$NC_ADMIN_PASSWORD}"
            setup/connect-nextcloud-to-miab.sh $NCDIR $NC_ADMIN_USER "$NC_ADMIN_PASSWORD" "$MAILINABOX_HOST" "$MAILINABOX_SERVICE_PASSWORD" "$ALERTS_EMAIL" "$MAILINABOX_SMARTHOST_AUTH_USER" "$MAILINABOX_SMARTHOST_AUTH_PASSWORD"
            rc=$?
            if [ $rc -eq 0 ]; then
                tools/editconf.py $STORAGE_ROOT/nextcloud/ciab_nextcloud.conf \
                                  "NC_ADMIN_PASSWORD='$NC_ADMIN_PASSWORD'"
                # ignore errors
            fi
        done
    fi
    
else
    # non-interactive
    if [ ! -z "$MAILINABOX_HOST" -a ! -z "$MAILINABOX_SERVICE_PASSWORD" ]; then
        # If a host.local name was supplied an ldaps connection will
        # always fail because the server's certificate will not have a
        # common name of host.local. We can at least try to convert it
        # to host.domain.tld, where domain.tld is this hosts's domain
        # name, and add an entry in /etc/hosts for it.
        convert_dot_local

        # save values for next time setup is run
        save_conf
        
        # execute the integration script that comes with MiaB-LDAP
        setup/connect-nextcloud-to-miab.sh $NCDIR $NC_ADMIN_USER "$NC_ADMIN_PASSWORD" "$MAILINABOX_HOST" "$MAILINABOX_SERVICE_PASSWORD" "$ALERTS_EMAIL" "$MAILINABOX_SMARTHOST_AUTH_USER" "$MAILINABOX_SMARTHOST_AUTH_PASSWORD"
    fi
    
fi


true

