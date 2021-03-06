
. setup/functions-miab.sh
. setup/functions-downloads-miab.sh

# turn off "strict" mode
set +e
set +u
set +o pipefail



#
# replace this mail-in-a-box function
#
function hide_output {
	# This function hides the output of a command unless the command fails
	# and returns a non-zero exit code.

	# Get a temporary file.
	OUTPUT=$(tempfile)

	# Execute command, redirecting stderr/stdout to the temporary file. Since we
	# check the return code ourselves, disable 'set -e' temporarily.
	#set +e
	$@ &> $OUTPUT
	E=$?
	#set -e

	# If the command failed, show the output that was captured in the temporary file.
	if [ $E != 0 ]; then
		# Something failed.
		echo
		echo FAILED: $@
		echo -----------------------------------------
		cat $OUTPUT
		echo -----------------------------------------
		exit $E
	fi

	# Remove temporary file.
	rm -f $OUTPUT
}


array_contains() {
	local searchfor="$1"
	shift
	local item
	for item; do
		[ "$item" == "$searchfor" ] && return 0
	done
	return 1
}

source_miab_script() {
    local script="$1"
    set -euo pipefail
    . "$script"
    . /etc/cloudinabox.conf
    set +e
    set +u
    set +o pipefail
}


get_nc_config_value() {
    # get a nextcloud config value
    # prior to calling:
    #    /etc/cloudinabox.conf must have been sourced
    #    locations.sh must have been sourced
    #    php or jq is installed
    local name="$1"
    local default_value="$2"
    local config_php="${3:-$NCSTORAGE/config/config.php}"
    local config_list="${4:-$NCSTORAGE/config.list}"

    local tmp="/tmp/stderr.$$"
    local code
    local errors=0
    
    # try config.php first, it will be more up-to-date because
    # config.list is only updated periodically by cron

    local phpx="$REQUIRED_PHP_EXECUTABLE"
    if [ -z "$phpx" -o ! -x "$phpx" ]; then
        phpx="/usr/bin/php"
    fi
    
    if [ -x "$phpx" -a -e "$config_php" ]; then
        local x
        x=$("$phpx" -r "
require '$config_php';
if (!array_key_exists('$name', \$CONFIG)) { print('DOES-NOT-EXIST'); }
else {print(\$CONFIG['$name']);}"
            2>"$tmp")
        code=$?
        
        if [ $code -ne 0 -o -z "$x" ]; then
            say_verbose "unable to get nextcloud config value for '$name' from $config_php ($code): $(cat $tmp)"
            let errors+=1
        else
            if [ "$x" != "DOES-NOT-EXIST" ]; then
                rm -f "$tmp"
                VALUE="$x"
                return 0
            else
                errors=0
                say_verbose "'$name' not found in $config_php"
            fi
        fi
    fi

    if [ -x /usr/bin/jq -a -e "$config_list" ]; then
        local x
        x=$(/usr/bin/jq -c ".system.$name" "$config_list" 2>$tmp | sed 's/"//g')
        code=$?
        if [ $code -ne 0 ]; then
            say_verbose "unable to get nextcloud config value for '$name' from $config_list ($code): $(cat $tmp)"
            let errors+=1
        elif [ "$x" == "null.." ]; then
            errors=0
            say_verbose "'.system.$name' not found in $config_list"
        else
            rm -f "$tmp"
            VALUE="$x"
            return 0
        fi
    fi

    rm -f "$tmp"
    if [ $errors -gt 0 ]; then
        return 1
    fi
    
    VALUE="$default_value"
    return 0
}


get_os_release() {
    if [ ! -z "$OS_NAME" ]; then
        return 0
    fi
    OS_NAME="$(. /etc/os-release; echo $NAME)"
    OS_VERSION_CODENAME="$(. /etc/os-release; echo $VERSION_CODENAME)"
    OS_MAJOR="$(. /etc/os-release; echo $VERSION_ID | awk -F. '{print $1}')"
    if [ "$OS_NAME" != "Ubuntu" ]; then
        die "Sorry, cloud-in-a-box is only supported on Ubuntu !"
    fi
}


get_required_php_version() {
    if [ ! -z "$REQUIRED_PHP_PACKAGE" ]; then
        return 0
    fi
    
    # set global  OS_* vars
    get_os_release

    # on return, these globals are set
    REQUIRED_NC_FOR_FRESH_INSTALLS="latest"
    REQUIRED_PHP_PACKAGE="php7.4"
    REQUIRED_PHP_VERSION="7.4"
    REQUIRED_PHP_EXECUTABLE="/usr/bin/php7.4"

    local os_desc="$OS_NAME $OS_MAJOR $OS_VERSION_CODENAME"
    
    # get the installed nextcloud version (if installed)
    if ! get_nc_config_value "version" ""
    then
        die "Error obtaining the installed nextcloud version!"
    fi

    if [ -z "$VALUE" ]; then
        # nextcloud is not installed, and no restored user-data either
        if [ $OS_MAJOR -le 18 ]; then
            # ubuntu 18 and below do not have php7.4, only php7.2, and only
            # nextcloud versions <= 20 support 7.2.
            REQUIRED_NC_FOR_FRESH_INSTALLS="latest-20"
            REQUIRED_PHP_PACKAGE="php7.2"
            REQUIRED_PHP_VERSION="7.2"
            REQUIRED_PHP_EXECUTABLE="/usr/bin/php7.2"
            say "Warning: this OS ($os_desc) will not support Nextcloud versions higher than 20. Upgrade $OS_NAME to get Nextcloud versions 21 and higher."
            return 0
        else
            return 0
        fi
    fi

    # nextcloud is already installed (or at least a backup of
    # user-data exists where we obtained the nextcloud version)
    local nc_ver="$VALUE"
    local nc_major="$(awk -F. '{print $1}' <<< "$nc_ver")"
    
    if [ $nc_major -lt 18 ]; then
        # nextcloud 17 and below do not support php 7.4
        if [ $OS_MAJOR -gt 18 ]; then
            die "The version of nextcloud installed is $nc_major, which requires php7.2. However, $os_desc does not support it"
        fi
        REQUIRED_PHP_PACKAGE="php7.2"
        REQUIRED_PHP_VERSION="7.2"
        REQUIRED_PHP_EXECUTABLE="/usr/bin/php7.2"
        return 0

    elif [ $nc_major -le 20 ]; then
        # nextcloud 18 to 20 (inclusive) support php7.2 and php7.4
        if [ $OS_MAJOR -le 18 ]; then
            # ubuntu 18 does not have php7.4, only php7.2
            REQUIRED_PHP_PACKAGE="php7.2"
            REQUIRED_PHP_VERSION="7.2"
            REQUIRED_PHP_EXECUTABLE="/usr/bin/php7.2"
            return 0
        fi
        REQUIRED_PHP_PACKAGE="php7.4"
        REQUIRED_PHP_VERSION="7.4"
        REQUIRED_PHP_EXECUTABLE="/usr/bin/php7.4"
        return 0

    else
        # nextcloud 21 and higher no longer support php7.2
        if [ $OS_MAJOR -le 18 ]; then
            die "Nextcloud version $nc_major is installed, however $os_desc does not have a version of php that supports it. 7.4 is required. An OS upgrade is required."
        fi
        
        REQUIRED_PHP_PACKAGE="php7.4"
        REQUIRED_PHP_VERSION="7.4"
        REQUIRED_PHP_EXECUTABLE="/usr/bin/php7.4"
        return 0
    fi
}



#
# LOAD GLOBAL VARIABLES
#

if [ ! -z "$STORAGE_ROOT" ]
then
    . "setup/locations.sh" || die "could not load setup/locations.sh"
    get_os_release
    get_required_php_version
    
else
    say_verbose "Warning: STORAGE_ROOT not set, not loading globals yet"
fi

