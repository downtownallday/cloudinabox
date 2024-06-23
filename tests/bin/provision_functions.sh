# source this file
#
# requires: lx_functions.sh
#

. "$(dirname "$BASH_SOURCE")/../lib/misc.sh"

provision_start() {
    local base_image="$1"
    local guest_mount_path="$2"

    # set these globals
    project="$(lx_guess_project_name)"
    inst="$(basename "$PWD")"
    provision_start_s="$(date +%s)"
    
    echo "Creating instance '$inst' from image $base_image"
    lx_launch_vm_and_wait \
        "$project" "$inst" "$base_image" "$guest_mount_path" \
        -c limits.cpu=2 -c limits.memory=1GiB \
        || return 1
}


provision_done() {
    local rc="$1"
    echo "Elapsed: $(elapsed_pretty "$provision_start_s" "$(date +%s)")"
    if [ $rc -ne 0 ]; then
        echo "Failed with code $rc"
        return 1
    else
        echo "Success!"
        return 0
    fi
}
