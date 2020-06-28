
. setup/functions-miab.sh
# turn off "strict" mode
set +e
set +u
set +o pipefail

declare -i verbose

while [ "$1" == "-v" ]; do
    let verbose="${verbose:-0} + 1"
    shift
done

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



die() {
    echo "FATAL: $1" 1>&2
    exit 1
}

is_verbose() {
    [ ${verbose:-0} -gt 0 ] && return 0
    return 1
}

say() {
    echo "$@"
}

say_verbose() {
    is_verbose && echo "$@"
    return 0
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

is_installed_mailinabox() {
    if [ -s /etc/mailinabox.conf -a -d "$STORAGE_ROOT/mail/mailboxes" ]; then
        return 0
    else
        return 1
    fi
}
