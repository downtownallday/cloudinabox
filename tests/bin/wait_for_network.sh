#!/bin/bash

idx=30
while [ $idx -gt 0 ]; do
    ping -c 1 ppa.launchpad.net >/dev/null 2>&1
    code=$?
    let idx-=1
    [ $code -eq 0 ] && exit 0
    if [ $idx -eq 0 ]; then
        echo "Timeout waiting for network"
        exit 1
    fi
    let x="$idx % 5"
    [ $x -eq 0 ] && echo "Waiting for network"
    sleep 1
done

exit 1
