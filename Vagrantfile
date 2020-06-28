# -*- mode: ruby -*-
# vi: set ft=ruby :
# Hint: to eliminate Ruby warnings from Vagrant, run:
#     export RUBYOPT="-W0"

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"

  # Network config: The machine must be connected to the public
  # web. However, we currently don't want to expose SSH since the
  # machine's box will let anyone log into it. So instead we'll put
  # the machine on a private network.
  config.vm.hostname = "cloudinabox.local"
  config.vm.network "private_network", ip: "192.168.50.4"

  config.vm.provision :shell, :inline => <<-SH
    # Set environment variables so that the setup script does
    # not ask any questions during provisioning. We'll let the
    # machine figure out its own public IP.
    export NONINTERACTIVE=1
    export PUBLIC_IP=auto
    export PUBLIC_IPV6=auto
    export PRIMARY_HOSTNAME=cloudinabox

    # Start the setup script.
    cd /vagrant
    setup/start.sh
SH
end
