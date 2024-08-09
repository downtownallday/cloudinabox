#!/bin/bash

#
# Parallel provisioning for test vms
#

. "$(dirname "$0")/../bin/lx_functions.sh"
. "$(dirname "$0")/../lib/color-output.sh"
. "$(dirname "$0")/../lib/misc.sh"

boxes=( vanilla-ehdd from-backup )
boxes_override="no"

project="$(lx_guess_project_name)"

# destroy running boxes
if [ "$1" = "-d" ]; then
    shift
    [ $# -gt 0 ] && boxes=( $* )
    for inst in $(lx_output_inst_list "$project" "n" "csv"); do
        if array_contains $inst ${boxes[*]}; then
            echo lxc --project "$project" delete $inst --force
            lxc --project "$project" delete $inst --force
        fi
    done
    exit 0
elif [ "$1" = "-h" -o "$1" = "--help" ]; then
    echo "usage: $0 [-d] [inst-name ...]"
    echo "  -d    delete/destroy running boxes"
    echo "  inst-name   an instance directory (instance name). defaults to: ${boxes[*]}"
    exit 0
fi

if [ $# -gt 0 ]; then
    boxes=( $* )
    boxes_override="yes"
fi

# set total parallel vms to (#cores minus 1)
MAX_PROCS=$(cat /proc/cpuinfo | grep processor | wc -l)
let MAX_PROCS-=1
[ $MAX_PROCS -eq 0 ] && MAX_PROCS=1

OUTPUT_DIR=out
#rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "MAX_PROCS=$MAX_PROCS"
echo "OUTPUT_DIR=$OUTPUT_DIR"

start_time="$(date +%s)"
 
# bring up in parallel
for inst in ${boxes[*]}; do
    outfile="$OUTPUT_DIR/$inst.out.txt"
    rm -f "$outfile"
    echo "Bringing up '$inst'. Output will be in: $outfile" 1>&2
    echo $inst
done | xargs -P $MAX_PROCS -I"INSTNAME" \
             sh -c '
cd "INSTNAME" && 
./provision.sh >'"../$OUTPUT_DIR/"'INSTNAME.out.txt 2>&1 && 
echo "EXITCODE: 0" >> '"../$OUTPUT_DIR/"'INSTNAME.out.txt || 
echo "EXITCODE: $?" >>'"../$OUTPUT_DIR/"'INSTNAME.out.txt
'

# output overall result"
H1 "Results"

rc=0
for inst in ${boxes[*]}; do
    file="$OUTPUT_DIR"/$inst.out.txt
    exitcode="$(tail "$file" | grep EXITCODE: | awk '{print $NF}')"
    echo -n "$inst: "
    if [ -z "$exitcode" ]; then
        danger "NO EXITCODE!"
        [ $rc -eq 0 ] && rc=2
    elif [ "$exitcode" == "0" ]; then
        elapsed="$(tail "$file" | grep ^Elapsed | awk -F: '{print $2}')"
        success "SUCCESS (${elapsed# })"
    else
        danger "FAILURE ($exitcode)"
        rc=1
    fi
done

# output elapsed time
end_time="$(date +%s)"
echo ""
echo "Elapsed time: $(elapsed_pretty $start_time $end_time)"

# exit
echo ""
echo "Guest VMs are running! Destroy them with:"
if [ "$boxes_override" = "no" ]; then
    echo "   $0 -d"
else
    echo "   $0 -d ${boxes[*]}"
fi
exit $rc
