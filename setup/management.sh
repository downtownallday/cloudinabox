#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

phpver="$REQUIRED_PHP_VERSION"

# install packages

apt_install duplicity certbot \
    || die "Unable to install packages"


# Create a backup directory and a random key for encrypting backups.

mkdir -p $STORAGE_ROOT/backup
if [ ! -f $STORAGE_ROOT/backup/secret_key.txt ]; then
    $(umask 077; openssl rand -base64 2048 > $STORAGE_ROOT/backup/secret_key.txt)
fi


create_backup_py() {
    # create backup.py from backup-miab.py
    # * modify the list of services to stop/start
    # * add an option to duplicity backups to exclude directory
    #   if a NOBACKUP file exists

    say_verbose "create management/backup.py from mail-in-a-box's backup.py"
    if grep ^WHITE_ management/backup-miab.py >/dev/null; then
        # just in case... to avoid any bad things happening in the
        # eval call below
        die "'WHITE_' found in management/backup-miab.py, refusing to continue"
    fi
    
    echo "# GENERATED FILE - DO NOT EDIT - GENERATED FROM backup-miab.py" > "management/backup.py" || die "Could not create backup.py"

    # Change the python code of the "perform_backup" function:
    #   1. comment out lines we don't want
    #   2. For the blocks of code that execute service_command("stop") and
    #   service_command("start"), comment them out, but also keep track of
    #   the python indent in WHITE_START/WHITE_STOP lines of the
    #   output. We'll replace them with the new code in the next step.

    awk  '
BEGIN { IN_DEF=0; DID_START=0; DID_STOP=0 }
{ WHITE=substr($0, 0, index($0,$1)-1) }

IN_DEF && /^def /                 { IN_DEF=0 }
!IN_DEF && /^def +perform_backup/ { IN_DEF=1 }

IN_DEF && /service_command.*start/ {
    if(!DID_START) print "WHITE_START=\""WHITE"\"";
    DID_START=1;
    print "# "$0;     
    next; }

IN_DEF && /service_command.*stop/ { 
    if(!DID_STOP) print "WHITE_STOP=\""WHITE"\"";
    DID_STOP=1;
    print "# "$0;    
    next; }

IN_DEF && /wait_for_service/ { print "# "$0; next }

{ print }
' "management/backup-miab.py" >>"management/backup.py" ||
        die "Could not append backup-miab.py to backup.py"


    # get the python indent for service_command(stop/start)

    eval "$(grep ^WHITE_ management/backup.py)"


    # replace the WHITE_START/WHITE_STOP lines with our code. This
    # code runs before a backup (stop_cmds) and after the backup
    # (start_cmds)

    local stop_cmds=(
        "code, ret = shell('check_output', ['/usr/bin/sudo', '-u', 'www-data', 'php', '/usr/local/nextcloud/occ', 'maintenance:mode', '--on'], capture_stderr=True, trap=True)"
        "if code != 0: print(ret)"
        "if code != 0: sys.exit(code)"
        "service_command('php${phpver}-fpm', 'stop', quit=True)"
        "service_command('redis-server', 'stop', quit=True)"
        "service_command('mariadb', 'stop', quit=True)"
    )
    
    local start_cmds=(
        "service_command('redis-server', 'start', quit=False)"
        "service_command('mariadb', 'start', quit=False)"
        "service_command('php${phpver}-fpm', 'start', quit=False)"
        "code, ret = shell('check_output', ['/usr/bin/sudo', '-u', 'www-data', 'php', '/usr/local/nextcloud/occ', 'maintenance:mode', '--off'], capture_stderr=True, trap=True)"
        "if code != 0: print(ret)"
    )

    local idx=0
    txt=""
    while [ $idx -lt ${#stop_cmds[*]} ]; do
        txt="${txt}${WHITE_STOP}${stop_cmds[$idx]}\n"
        let idx+=1
    done
    sed -i "s|^WHITE_STOP=.*\$|$txt|" management/backup.py ||
        die "Could not modify backup.py"

    local idx=0
    txt=""
    while [ $idx -lt ${#start_cmds[*]} ]; do
        txt="${txt}${WHITE_START}${start_cmds[$idx]}\n"
        let idx+=1
    done
    sed -i "s|^WHITE_START=.*\$|$txt|" management/backup.py ||
        die "Could not modify backup.py"


    # add --exclude-if-present NOBACKUP to duplicicy call
    sed -i 's|"--exclude"\s*,\s*backup_root|"--exclude-if-present", "NOBACKUP", &|g' management/backup.py ||
        die "Could not add --exclude-if-present to backup.py"

    
    # test validity
    python3 -m py_compile management/backup.py ||
        die "The generated file backup.py failed compilation! Cannot continue"
}


create_utils_py() {
    # create utils.py from utils-miab.py
    # * change the conf file location

    say_verbose "create management/utils.py from mail-in-a-box's utils.py"
    echo "# GENERATED FILE - DO NOT EDIT - GENERATED FROM utils-miab.py" > management/utils.py || die "Could not create utils.py"
    cat "management/utils-miab.py" >>"management/utils.py" || die "Could not append utils-miab.py"
    sed -i 's/\/etc\/mailinabox\.conf/\/etc\/cloudinabox.conf/' "management/utils.py"
}


create_ssl_certificates_py() {
    # create ssl_certificates.py fromm ssl_certificates-miab.py
    # * modify the list of services to restart (ones that use a new cert)

    say_verbose "create management/ssl_certificates.py from mail-in-a-box's"
    echo "# GENERATED FILE - DO NOT EDIT - GENERATED FROM ssl_certificates-miab.py" > "management/ssl_certificates.py" || die "Could not create ssl_certificates.py"
    awk '/check_call/ && /(slapd|postfix|dovecot)/ {next;} {print $0}' \
        "management/ssl_certificates-miab.py" >> \
        "management/ssl_certificates.py" ||
        die "Could not append ssl_certificates-miab.py to ssl_certificates.py"
    sed -i "s/from dns_update/from web_update/g" management/ssl_certificates.py || die "Could not modify ssl_certificates.py"
    sed -i "s/get_dns_zones/get_web_zones/g" management/ssl_certificates.py || die "Could not modify ssl_certificates.py"
}



create_backup_py
create_utils_py
create_ssl_certificates_py


# set up cron job for daily_tasks (status checks, backups, etc)

cat > /etc/cron.d/cloudinabox-nightly << EOF
# Cloud-in-a-Box --- Do not edit / will be overwritten on update.
# Run nightly tasks: backup, status checks.
0 3 * * *	root	(cd `pwd` && management/daily_tasks.sh)
EOF

