#!/bin/bash

vagrant destroy -f
rm -f prepcode.txt

for plugin in "vagrant-vbguest" "vagrant-reload"
do
    if ! vagrant plugin list | grep -F "$plugin" >/dev/null; then
        vagrant plugin install "$plugin" || exit 1
    fi
done

if [ ! -e "keys/id_ed25519" ]; then
    mkdir -p keys
    ssh-keygen -f keys/id_ed25519 -C "preloaded-key" -N "" -t ed25519
fi


vagrant box update

for box in preloaded-ubuntu-jammy64 preloaded-ubuntu-noble64
do

    if [ ! -z "$1" -a "$box" != "$1" ]; then
        echo "SKIPPING: $box"
        continue
    fi
    echo "-------------------------------------------------------------"
    echo "STARTING: $box"
    echo "-------------------------------------------------------------"
    vagrant up $box | tee /tmp/$box.out
    upcode=$?
    
    if [ $upcode -eq 0 -a ! -e "./prepcode.txt" ] && grep -F 'Authentication failure' /tmp/$box.out >/dev/null; then
        # note: upcode is 0 only if config.vm.boot_timeout is set.
        # If this works it may be an indication that ruby's internal
        # ssh does not support the algorithm required by the server,
        # or the public key does not match (vagrant and vm out of
        # sync)
        echo ""
        echo "VAGRANT AUTHENTICATION FAILURE - TRYING LOOSER ALLOWED SSHD ALGS"
        if vagrant ssh $box -c "sudo bash -c 'echo PubkeyAcceptedAlgorithms +ssh-rsa > /etc/ssh/sshd_config.d/ciab.conf; sudo systemctl restart sshd'"; then
            vagrant halt $box
            vagrant up $box
            upcode=$?
        fi
    fi
        
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
    rm -f $box.box
    vagrant package --output $box.box $box

    vagrant destroy -f $box
    cached_name="$(sed 's/preloaded-/preloaded-ciab-/' <<<"$box")"
    vagrant box remove --provider virtualbox $cached_name
done

