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

provision_shell() {
    # provision_start must have been called first!
    local remote_path="/tmp/provision.sh"
    local lxc_flags="--uid 0 --gid 0 --mode 755 --create-dirs"
    if [ ! -z "$1" ]; then
        lxc --project "$project" file push "$1" "${inst}${remote_path}" $lxc_flags || return 1
        
    else
        local tmp=$(mktemp)
        echo "#!/bin/sh" >"$tmp"
        cat >>"$tmp"
        lxc --project "$project" file push "$tmp" "${inst}${remote_path}" $lxc_flags || return 1
        rm -f "$tmp"
    fi

    lxc --project "$project" exec "$inst" --cwd / --env PROVISION=true \
        -- "$remote_path"
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
