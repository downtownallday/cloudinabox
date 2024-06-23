#!/bin/bash

. setup/functions.sh     || exit 1

if [ "$OS_NAME" != "Ubuntu" ]; then
    die "Sorry, cloud-in-a-box is only supported on Ubuntu Linux"
fi

if [ $OS_MAJOR -ne 22 -a $OS_MAJOR -ne 24 ]; then
    die "Sorry, this version of cloud-in-a-box only works on Ubuntu 24 (Noble) or Ubuntu 22 (Jammy). The last supported version for older Ubuntu 20 (Focal) was v0.8 and Ubuntu 18 (Bionic) v0.4."
fi

if [ $EUID -ne 0 ]; then
    echo "Must be run as root"
    exit 1
fi

# if encryption-at-rest is enabled, make sure the drive is mounted
ehdd/mount.sh    

read_hostname() {
    hostname="${PRIMARY_HOSTNAME:-$(get_default_hostname)}"
    if [ -z "$NONINTERACTIVE" ]; then
        echo "Enter the hostname that user's will use to access Nextcloud on this box"
        read -p  "[$hostname] " -i "$hostname" ans_hostname
        [ ! -z "$ans_hostname" ] && hostname="$ans_hostname"
    fi
}

read_alerts_email() {
    alerts_email="${ALERTS_EMAIL:-}"
    if [ -z "$NONINTERACTIVE" ]; then
        echo "Enter the email address where results from daily tasks are sent"
        if [ -z "$alerts_email" ]; then
            read -p "[<currently unset>] " -i "$alerts_email" ans_email
        else
            read -p "[$alerts_email] " -i "$alerts_email" ans_email
            [ -z "$ans_email" ] && ans_email="$alerts_email"
        fi
        alerts_email="$ans_email"
    fi
}


create_conf() {
    # create or modify /etc/cloudinabox.conf
    #
    # if an existing /etc/cloudinabox.conf exists, it should be loaded
    # prior to calling this function
    
    local publicip=$(get_publicip_from_web_service 4)
    [ -z "$publicip" ] && publicip=$(get_default_privateip 4)
    local publicip=$(get_publicip_from_web_service 4)
    [ -z "$publicip" ] && publicip=$(get_default_privateip 4)
    local privateip=$(get_default_privateip 4)

    local publicipv6=$(get_publicip_from_web_service 6)
    [ -z "$publicipv6" ] && publicipv6=$(get_default_privateip 6)
    local publicipv6=$(get_publicip_from_web_service 6)
    [ -z "$publicipv6" ] && publicipv6=$(get_default_privateip 6)
    local privateipv6=$(get_default_privateip 6)
    ALERTS_EMAIL_HAS_CHANGED=no

    # normalize LOCAL_MODS_DIR
    LOCAL_MODS_DIR_NORM="$(realpath -m "${LOCAL_MODS_DIR:-local}")"
        
    read_hostname
    read_alerts_email
    
    if [ ! -e /etc/cloudinabox.conf ]; then
        say_verbose "Creating new /etc/cloudinabox.conf"
        FIRST_TIME_SETUP=1  # for miab borrowed scripts (eg. system-miab.sh)
        
        cat >/etc/cloudinabox.conf <<EOF
STORAGE_ROOT=${STORAGE_ROOT:-/home/user-data}
STORAGE_USER=${STORAGE_USER:-user-data}
PRIMARY_HOSTNAME=$hostname
TIMEZONE=
ALERTS_EMAIL=$alerts_email
PUBLIC_IP=$publicip
PUBLIC_IPV6=$publicipv6
PRIVATE_IP=$privateip
PRIVATE_IPV6=$privateipv6
LOCAL_MODS_DIR=$LOCAL_MODS_DIR_NORM
EOF
    else
        if [ "$publicip" != "$PUBLIC_IP" ]; then
            tools/editconf.py /etc/cloudinabox.conf "PUBLIC_IP=$publicip"
        fi
        
        if [ "$privateip" != "$PRIVATE_IP" ]; then
            tools/editconf.py /etc/cloudinabox.conf "PRIVATE_IP=$privateip"
        fi

        if [ "$publicipv6" != "$PUBLIC_IPV6" ]; then
            tools/editconf.py /etc/cloudinabox.conf "PUBLIC_IPV6=$publicipv6"
        fi
        
        if [ "$privateipv6" != "$PRIVATE_IPV6" ]; then
            tools/editconf.py /etc/cloudinabox.conf "PRIVATE_IPV6=$privateipv6"
        fi

        if [ "$hostname" != "$PRIMARY_HOSTNAME" ]; then
            tools/editconf.py /etc/cloudinabox.conf "PRIMARY_HOSTNAME=$hostname"
        fi

        if [ "$LOCAL_MODS_DIR" != "$LOCAL_MODS_DIR_NORM" ]; then
            tools/editconf.py /etc/cloudinabox.conf "LOCAL_MODS_DIR=$LOCAL_MODS_DIR_NORM"
        fi
        
        if [ "$alerts_email" != "$ALERTS_EMAIL" ]; then
            ALERTS_EMAIL_HAS_CHANGED=yes
            tools/editconf.py /etc/cloudinabox.conf "ALERTS_EMAIL=$alerts_email"
        fi
    fi
    
    . /etc/cloudinabox.conf

    # create the storage user and home directory
    if ! id -u $STORAGE_USER >/dev/null 2>&1; then
        useradd -m $STORAGE_USER
    fi
    if [ ! -d $STORAGE_ROOT ]; then
        mkdir -p $STORAGE_ROOT
    fi
    if [ ! -f $STORAGE_ROOT/cloudinabox.version ]; then
        echo "1" > $STORAGE_ROOT/cloudinabox.version
        chown $STORAGE_USER:$STORAGE_USER $STORAGE_ROOT/cloudinabox.version
    fi

    # we borrow scripts from mail-in-a-box, which require that this
    # exists
    [ ! -e /etc/mailinabox.conf ] && touch /etc/mailinabox.conf
}



# create or modify /etc/cloudinabox.conf

[ -e /etc/cloudinabox.conf ] && . /etc/cloudinabox.conf
create_conf


# install system packages (includes setting /etc/timezone)

say_verbose "start: system.sh"
. ./setup/system.sh
if [ "$TIMEZONE" != "$(cat /etc/timezone)" ]; then
    TIMEZONE="$(cat /etc/timezone)"
    tools/editconf.py /etc/cloudinabox.conf "TIMEZONE=$TIMEZONE"
fi


# install the rest of what we need

say_verbose "start: php.sh"
. ./setup/php.sh
say_verbose "start: redis.sh"
. ./setup/redis.sh
say_verbose "start: sql.sh"
. ./setup/sql.sh
say_verbose "start: ssl.sh"
. ./setup/ssl.sh
say_verbose "start: management.sh"
. ./setup/management.sh
say_verbose "start: nginx.sh"
. ./setup/nginx.sh
say_verbose "start: nextcloud.sh"
. ./setup/nextcloud.sh
say_verbose "start: integrate_miab_ldap.sh"
. ./setup/integrate-miab-ldap.sh



# Interactively register with Let's Encrypt

say_verbose "start: lets encrypt interactive registration"
config_dir=$STORAGE_ROOT/ssl/lets_encrypt
accounts_directory=$config_dir/accounts/acme-v02.api.letsencrypt.org/directory
if [ ! -d $accounts_directory -o -z "$(ls -A $accounts_directory 2>/dev/null)" ]
then
    # create new certbot account / register with letsencrypt
    if [ -z "$ALERTS_EMAIL" ]; then
        certbot register --register-unsafely-without-email --config-dir $config_dir --agree-tos
    else
        certbot register --non-interactive -m "$ALERTS_EMAIL" --no-eff-email --config-dir $config_dir --agree-tos
    fi
    
elif [ "$ALERTS_EMAIL_HAS_CHANGED" == "yes" ]; then
    if [ -z "$ALERTS_EMAIL" ]; then
        certbot update_account --register-unsafely-without-email --config-dir $config_dir --agree-tos
    else
        certbot update_account --non-interactive -m "$ALERTS_EMAIL" --no-eff-email --config-dir $config_dir --agree-tos
    fi
    
fi


#
# Setup mods
source_miab_script setup/setupmods-miab.sh


# run status checks
python3 management/status_checks.py
say ""

# Warn if ssmtp is not installed

if [ ! -z "$ALERTS_EMAIL" -a ! -x /usr/sbin/ssmtp ]; then
    say ""
    say "To receive email alerts install and configure ssmtp. See:"
    say "   https://help.ubuntu.com/community/EmailAlerts"
fi


# Done

if openssl x509 -text -in $STORAGE_ROOT/ssl/ssl_certificate.pem  | grep -F "Temporary-Mail-In-A-Box-CA" >/dev/null
then
    say ""
    say "A temporary web certificate is installed. An attempt to obtain a valid certificate from Let's Encrypt will be made at 3:00 AM. To perform the certificate provisioning now, run 'python3 management/ssl_certificates.py'" | fold -s
fi

say ""
say "Access your server at:"
ips=($(echo "$PUBLIC_IP $PRIVATE_IP $PUBLIC_IPV6 $PRIVATE_IPV6 $(hostname -I)" | sed 's/ /\n/g' | uniq))
for ip in "${ips[@]}"; do
    say "   https://$ip/"
done

say ""
say "Your nextcloud admin account credentials are:"
say "   user: $NC_ADMIN_USER"
say "   pass: $NC_ADMIN_PASSWORD"
say ""
say "These credentials are also in:"
say "   $STORAGE_ROOT/nextcloud/ciab_nextcloud.conf"

say ""
say "Done."

