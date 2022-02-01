#!/bin/bash

vagrant destroy -f
rm -f prepcode.txt

for plugin in "vagrant-vbguest" "vagrant-reload"
do
    if ! vagrant plugin list | grep -F "$plugin" >/dev/null; then
        vagrant plugin install "$plugin" || exit 1
    fi
done


vagrant box update

for box in "preloaded-ubuntu-focal64" "preloaded-ubuntu-jammy64"
do
    vagrant up $box
    upcode=$?
    if [ $upcode -ne 0 -a ! -e "./prepcode.txt" ]
    then
        # a reboot may be necessary if guest addtions was newly
        # compiled by vagrant plugin "vagrant-vbguest"
        echo ""
        echo "VAGRANT UP RETURNED $upcode -- RETRYING AFTER REBOOT"
        vagrant halt $box
        vagrant up $box
        upcode=$?
    fi

    prepcode=$(cat "./prepcode.txt")
    rm -f prepcode.txt
    echo ""
    echo "VAGRANT UP RETURNED $upcode"
    echo "PREPVM RETURNED $prepcode"

    if [ "$prepcode" != "0" -o $upcode -ne 0 ]; then
        echo "FAILED!!!!!!!!"
        vagrant destroy -f $box
        exit 1
    fi

    if vagrant ssh $box -- cat /var/run/reboot-required; then
        vagrant reload $box
    fi

    vagrant halt $box
    vagrant package $box
    rm -f $box.box
    mv package.box $box.box

    vagrant destroy -f $box
    cached_name="$(sed 's/preloaded-/preloaded-ciab-/' <<<"$box")"
    vagrant box remove $cached_name
done

