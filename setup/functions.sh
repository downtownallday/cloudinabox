
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
	OUTPUT=$(mktemp)

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

    # read the supported nextcloud versions matix file
    local phpver
    phpver=$(awk -F: "/^${OS_MAJOR}:/ { print \$2 }" conf/nextcloud_os_matrix.txt)
    [ $? -ne 0 ] && die "Unable to read conf/nextcloud_os_matrix.txt"
    [ -z "$phpver" ] && die "Unsupported OS version (OS_MAJOR=$OS_MAJOR) - see conf/nextcloud_os_matrix.txt"
    ncmin=$(awk -F: "/^${OS_MAJOR}:/ { print \$3 }" conf/nextcloud_os_matrix.txt)
    ncmax=$(awk -F: "/^${OS_MAJOR}:/ { print \$4 }" conf/nextcloud_os_matrix.txt)
    [ -z "$ncmin" ] && die "Invalid value for nextcloud min/max in conf/nextcloud_os_matrix.txt"
    say_verbose "Nextcloud versions supported by this OS: ${ncmin}-${ncmax}"

    
    # on return, these globals are set
    REQUIRED_NC_FOR_FRESH_INSTALLS="latest"
    [ ! -z "$ncmax" ] && REQUIRED_NC_FOR_FRESH_INSTALLS="latest-$ncmax"
    REQUIRED_PHP_PACKAGE="php$phpver"
    REQUIRED_PHP_VERSION="$phpver"
    REQUIRED_PHP_EXECUTABLE="/usr/bin/php$phpver"


    local os_desc="$OS_NAME $OS_MAJOR $OS_VERSION_CODENAME"
    
    # get the installed nextcloud version (if installed)
    if ! get_nc_config_value "version" ""
    then
        die "Error obtaining the installed nextcloud version!"
    fi

    if [ -z "$VALUE" ]; then
        # nextcloud is not installed, and no restored user-data either
        if [ ! -z "$ncmax" ]; then
            local ncmax_plus_1="$ncmax"
            let ncmax_plus_1+=1
            say "Warning: this OS ($os_desc) will not support Nextcloud versions higher than $ncmax. Upgrade $OS_NAME to get Nextcloud versions $ncmax_plus_1 and higher."
        fi
            
        return 0
    fi

    # nextcloud is already installed (or at least a backup of
    # user-data exists where we obtained the nextcloud version)
    local nc_ver="$VALUE"
    local nc_major="$(awk -F. '{print $1}' <<< "$nc_ver")"

    local nc

    if [ $nc_major -lt $ncmin ]; then
        die "The version of Nextcloud installed is $nc_major, which requires a version of php that the OS doesn't support. The OS only supports Nextcloud versions ${ncmin}-${ncmax}."
    fi

    if [ ! -z "$ncmax" ]; then
        if [ $nc_major -gt $ncmax ]; then
            die "The version of Nextcloud installed is $nc_major, which requires a version of php that the OS doesn't support. The OS only supports Nextcloud versions ${ncmin}-${ncmax}."
        fi
    fi

    return 0
}



#
# LOAD GLOBAL VARIABLES
#

get_os_release

if [ ! -z "$STORAGE_ROOT" ]
then
    . "setup/locations.sh" || die "could not load setup/locations.sh"
    get_required_php_version    
else
    say_verbose "Warning: STORAGE_ROOT not set, not loading globals yet"
fi

