#!/bin/bash

show() {
    local project="$1"
    local which=$2
    if [ -z "$which" -o "$which" = "instances" ]; then
        lxc --project "$project" list -c enfsd -f csv | sed "s/^/    /"
    fi

    if [ -z "$which" -o "$which" = "images" ]; then
        lxc --project "$project" image list -c lfsd -f csv | sed "s/^/    $project,/"
    fi
}

global="no"
if [ $# -gt 0 ]; then
    projects=( "$@" )
else
    global="yes"
    projects=( $(lxc project list -f csv | awk -F, '{print $1}' | sed 's/ .*$//') )
fi

if [ "$global" = "yes" ]; then
    echo "** projects"
    idx=0
    while [ $idx -lt ${#projects[*]} ]; do
        echo "    ${projects[$idx]}"
        let idx+=1
    done
else
    echo "Project: ${projects[*]}"
fi


echo "** images"
idx=0
while [ $idx -lt ${#projects[*]} ]; do
    project="${projects[$idx]}"
    let idx+=1
    show "$project" images $verbose
done

echo "** instances"
idx=0
while [ $idx -lt ${#projects[*]} ]; do
    project="${projects[$idx]}"
    let idx+=1
    show "$project" instances $verbose
done
