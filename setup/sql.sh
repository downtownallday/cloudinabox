#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

#
# setup & configure mariadb
#

install_packages() {
    say "Installing mariadb"
    apt_install mariadb-server || die "Unable to install mariadb"
}

create_sql_conf() {
    local conf="$CIAB_SQL_CONF"
    if [ ! -e "$conf" ]; then
        say_verbose "Creating new $conf"
        mkdir -p "$(dirname "$conf")" || die "Unable to create directory for $conf"
        chmod 755 "$(dirname "$conf")"
        cat > "$conf" <<EOF
SQL_ROOT_PASSWORD=
DATA_DIR_CREATED=no
DATA_DIR_SECURED=no
EOF
        [ $? -ne 0 ] && die "Unable to create $conf"
        chmod 0600 "$conf"
    fi

    . "$conf"
}

config_server() {
    # Modify the server configuration file:
    say_verbose "Setting server config"

    # get system available memory
    local avail
    let avail=$(free -k | awk '/^Mem/ { print $7 }')

    # use 70% for Innodb buffer pool size
    let avail="$avail * 7 / 10 / 1024"

    cat > /etc/mysql/mariadb.conf.d/51-server.cnf <<EOF
[mariadbd]
binlog_format=ROW
transaction_isolation=READ-COMMITTED
datadir=$SQL_DATADIR
innodb_buffer_pool_size=${avail}M
performance_schema = off
EOF
}


update_apparmor() {
    local profile="/etc/apparmor.d/mariadbd"
    local profile_local="/etc/apparmor.d/local/mariadbd"
    if [ ! -e "$profile" ]; then
        # no profile - probably older version of Ubuntu / mariadb
        return 0
    fi

	# Update mariadb's access rights under AppArmor so that it has
	# access to database files in the user-data location

    rm -f "$profile_local" || return 1
    
    if [ "${1:-}" = "init" ]; then
        # the mariadb-install-db script requires setuid/setgid
	    cat > "$profile_local" <<EOF
# allow mariadb to switch from root to unprivileged account
capability setuid,
capability setgid,

EOF
    fi
    cat >> "$profile_local" <<EOF
# allow r/w/lock to database data files
$SQL_DATADIR/ r,
$SQL_DATADIR/** rwk,
EOF
	chmod 0644 "$profile_local" || return 1

	# Load settings into the kernel if AppArmor is enabled
	if aa-status --enabled; then
		/usr/sbin/apparmor_parser -r "$profile" || return 1
	fi
}


create_datadir() {
    if [ "$DATA_DIR_CREATED" = "yes" ]; then
        return 0
    fi

    local failed=no

    say_verbose "Initialize sql data directory"
    mkdir -p "$SQL_DATADIR" || die "Unable to create $SQL_DATADIR"
    chmod 770 "$SQL_DATADIR" || failed=yes
    chown mysql "$SQL_DATADIR" || failed=yes
    mkdir -p "$SQL_DATABACKUPDIR" || die "Unable to create $SQL_DATABACKUPDIR"
    chmod 750 "$SQL_DATABACKUPDIR" || failed=yes

    # make sure systemd and AppArmor allow rw access to
    # /home/user-data
    #
    # The mariadb-install-db script runs a new instance of mariadbd
    # (so it's ok to allow the one controlled by systemd to continue
    # to run). However, the new mariadb instance requires
    # setuid/setgid apparmor permissions. So, we allow it, run the
    # script, then take it away.

    say_verbose "Update apparmor and systemd permissions"
    fix_systemd || failed=yes
    update_apparmor "init" || failed=yes

    local tmp="/tmp/sql.$$"
   
    if [ "$failed" == "no" ]; then
        local xargs=()
        is_verbose && xargs+=(--verbose)
        if ! mariadb-install-db --user=mysql --datadir="$SQL_DATADIR" "${xargs[@]}" >"$tmp" 2>&1
        then
            cat "$tmp"
            echo "Also look for logs in /var/log"
            failed=yes
        fi
    fi

    rm -f "$tmp"
    update_apparmor || failed=yes
    
    if [ "$failed" == "yes" ]; then
        say "Mariadb setup failed. You may need to manually delete $SQL_DATADIR"
        return 1
    else
        tools/editconf.py "$CIAB_SQL_CONF" "DATA_DIR_CREATED=yes"
        DATA_DIR_CREATED=yes
    fi
    return 0
}

fix_systemd() {
    # don't start mysqld_safe - run mysqld under systemd
    systemctl stop mysql
    systemctl disable mysql >/dev/null 2>&1
    
    # The ProtectHome setting prevents mariadb from writing in /home,
    # so override the default systemd service file for mariadb
    local d="/etc/systemd/system/mariadb.service.d"
    mkdir -p "$d" || die "Could not create $d"
    cat > "$d/cloudinabox.conf" <<EOF
# Generated file will be overwritten - do not edit
[Service]
ProtectHome=false
EOF
    [ $? -ne 0 ] && die "Could not create $d/cloudinabox.conf"

    # refresh systemd so it sees the file
    systemctl daemon-reload 
}

store_root_password() {
    # place the root password in:
    #     /etc/mysql/debian.cnf
    #     $HOME/.my.cnf

    # The /etc/mysql/debian-start script does database checks and
    # upgrades every time the server is started and needs the root
    # password...
    local escaped_pass="$(awk '{ gsub("/", "\\/", $0); print $0}' <<<$SQL_ROOT_PASSWORD)"
    sed -i "s/password\s*=.*/password='$escaped_pass'/g" \
        /etc/mysql/debian.cnf
    [ $? -ne 0 ] &&
        die "Unable to edit /etc/mysql/debian.cnf"

    # For convenience accessing the database from the command line, save
    # the root password in $HOME/.my.cnf
    cat >$HOME/.my.cnf <<EOF
[client]
user=root
password='$SQL_ROOT_PASSWORD'

[mysql]
database=${NC_SQL_DB:-nextclouddb}
EOF
    [ $? -ne 0 ] &&
        say "WARNING: could not create $HOME/.my.cnf"
    
    if [ ! -z "$SUDO_USER" ]; then
        chgrp $SUDO_USER $HOME/.my.cnf ||
            say "WARNING: could not change group of $HOME/.my.cnf"
        chmod 640 $HOME/.my.cnf ||
            say "WARNING: could not set permissions on $HOME/.my.cnf"
    else
        chmod 600 $HOME/.my.cnf ||
            say "WARNING: could not set permissions on $HOME/.my.cnf"
    fi
}

secure_server() {
    if [ "$DATA_DIR_SECURED" == "yes" ]; then
        return 0
    fi
    # secure the RUNNING server
    say_verbose "Secure the server"
    #local pass
    #read -r -s -p "Enter a password for the mariadb root account: " pass
    #[ $? -ne 0 ] && die "Password read failed"
    #echo ""
    local pass="$(generate_password 32)"
    SQL_ROOT_PASSWORD="$pass"

    # set the root password and secure installation
    mysql -u root --password='' --database=mysql <<EOF
-- set root password
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$pass');

-- delete anon users
delete from user where User='';

-- ensure root cannot log in remotely
delete from user where User='root' and Host not in ('localhost','127.0.0.1','::1');

-- drop the test database
drop database if exists test;
delete from mysql.db where Db='test' or Db='test\_%';

-- flush
flush privileges;
EOF
    [ $? -ne 0 ] && die "Unable to set root password and secure the server"

    tools/editconf.py "$CIAB_SQL_CONF" \
                      "DATA_DIR_SECURED=yes" \
                      "SQL_ROOT_PASSWORD='$SQL_ROOT_PASSWORD'"
    [ $? -ne 0 ] && die "Unable to edit $CIAB_SQL_CONF"

    DATA_DIR_SECURED=yes
}

# install system packages
install_packages || die "Unable to continue"

# create or load STORAGE_ROOT/sql/ciab_sql.conf
create_sql_conf      || die "Unable to continue"

# create mariadb.cnf file in /etc/mysql
config_server    || die "Unable to continue"

# create fresh data directory, if needed
create_datadir   || die "Installation failed, unable to continue"

systemctl restart mariadb || die "mariadb would not start!"

# secure the server - only needs to be done once - on RUNNING server
secure_server

# store the root password in other locations as well
store_root_password


