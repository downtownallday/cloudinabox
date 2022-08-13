#!/bin/bash

# synchronize with miab code
#
# the purpose of this script is to update (copy) Mail-in-a-Box LDAP
# files that are used in this project into this project's source tree
#

# load array_contains function
. tests/lib/misc.sh || exit 1

# defaults and options
MYDIR=$(dirname "$0")
miabdir=$MYDIR/../mailinabox
ciabdir=$MYDIR
dry_run=false

usage() {
    echo "usage: $0 [--dry-run] [--miabdir <dir>]"
    exit 1
}


# process command line
while [ $# -gt 0 ]; do
    if [ "$1" == "--dry-run" ]; then
        dry_run=true
        shift
    elif [ "$1" == "--miabdir" ]; then
        shift
        [ $# -eq 0 ] && usage
        miabdir="$1"
        shift
    else
        usage
    fi
done


if [ ! -e "$miabdir" ]; then
    echo "Does not exist: $miabdir"
    exit 1
fi

if [ ! -e "$miabdir/setup/ldap.sh" ]; then
    echo "Not a MiaB-LDAP source tree. Does not exist: $miabdir/setup/ldap.sh"
    exit 1
fi


sync_recursive() {
    local src="$1"
    local dst="$2"
    if $dry_run; then
        echo "Syncing $dst"
        rsync -a --dry-run "$src" "$dst"
    else
        rsync -v -a "$src" "$dst"
    fi
}

# sync whole directories
sync_recursive "$miabdir/tests/lib/" "tests/lib"
sync_recursive "$miabdir/tests/assets/ssl/" "tests/assets/ssl"


# automatic files (source file in 'ciab_files' with corresponding
# destination in 'miab_files')
ciab_files=(
    ./tests/suites/_init.sh
    ./conf/nginx-ssl.conf
    ./setup/connect-nextcloud-to-miab.sh
    ./setup/mods.available/README.md
    ./setup/mods.available/coturn.sh
    ./setup/mods.available/unattended-upgrades-mail.sh
)
miab_files=(
    $miabdir/tests/suites/_init.sh
    $miabdir/conf/nginx-ssl.conf
    $miabdir/setup/mods.available/connect-nextcloud-to-miab.sh
    $miabdir/setup/mods.available/README.md
    $miabdir/setup/mods.available/coturn.sh
    $miabdir/setup/mods.available/unattended-upgrades-mail.sh
)


# files that end in -miab or _miab
$dry_run && echo "Sync select files and ones that end in -miab"
pushd "$ciabdir" >/dev/null
for f in $(find . -name \*-miab.\*) $(find . -name \*_miab.\*)
do
    skipped=""
    case $f in
        *~)
            skipped="emacs backup file"
            ;;
        *__pycache__*)
            skipped="python cache file"
            ;; # skip python cache
        *)
            if [ $(awk -F/ '{print NF}' <<<"$f") -le 2 ]
            then
                skipped="root file"
            elif array_contains "$f" "${ciab_files[@]}"
            then
                skipped="automatic file"
            else
                ciab_files+=($f)
                miab_file="$(sed 's/[-_]miab\././' <<< "$f")"
                miab_files+=( "$miabdir/$miab_file" )
            fi
            ;;
    esac
    $dry_run && [ ! -z "$skipped" ] && echo " SKIP: $f [$skipped]"
done
popd >/dev/null



process() {
    src="$1"
    dst="$2"
    changed=false

    if [ ! -e "$dst" ]; then
        changed=true
    else
        diff -q -s "$src" "$dst" >/dev/null
        if [ $? -eq 1 ]; then
            changed=true
        fi
    fi        
        
    if $dry_run; then
        if [ ! -e "$src" ]; then
            echo "ERROR: DOES NOT EXIST: $src"
            return 2

        elif $changed; then
            [ ! -e "$dst" ] && dst="$dst (DOES NOT EXIST)"
            echo " COPY:  $src -> $dst"
            return 1
            
        else
            echo " SAME:  $src <=> $dst"
            return 0
        fi
    else

        if $changed; then
            echo -n "COPY: "
            cp --verbose "$src" "$dst"
            [ $? -eq 0 ] && return 1
            return 2
        else
            return 0
        fi
    fi
}


idx=0
count_copied=0
while [ $idx -lt ${#miab_files[*]} ]; do
    process "${miab_files[$idx]}" "${ciab_files[$idx]}"
    [ $? -eq 1 ] && let count_copied+=1
    let idx+=1
done

echo ""
echo "$count_copied copied"

