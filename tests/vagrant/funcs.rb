
def use_preloaded_box(obj, name, preloaded_dir=".")
  _name=name.sub! '/','-'  # ubuntu/bionic64 => ubuntu-bionic64
  if File.file?("#{preloaded_dir}/preloaded/preloaded-#{_name}.box")
    # box name needs to be unique on the system
    obj.vm.box = "preloaded-ciab-#{_name}"
    obj.vm.box_url = "file://" + Dir.pwd + "/#{preloaded_dir}/preloaded/preloaded-#{_name}.box"
    obj.ssh.private_key_path = "#{preloaded_dir}/preloaded/keys/id_ed25519"
    if Vagrant.has_plugin?('vagrant-vbguest')
      # do not update additions when booting this machine
      obj.vbguest.auto_update = false
    end
  else
    obj.vm.box = name
  end
end

# Grab the name of the default interface
$default_network_interface = `ip route | awk '/^default/ {printf "%s", $5; exit 0}'`
