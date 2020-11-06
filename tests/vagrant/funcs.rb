class Testing
  @groups = [ ]
  def initialize()
    @groups = (ENV["testing"] || "dev").split(',')
  end
  
  def group(name)
    return @groups.include?(name) || @groups.include?('all')
  end

  def say_groups()
    puts("Testing groups: #{@groups}")
  end
end


def use_preloaded_box(obj, name, preloaded_dir=".")
  _name=name.sub! '/','-'  # ubuntu/bionic64 => ubuntu-bionic64
  if File.file?("#{preloaded_dir}/preloaded/preloaded-#{_name}.box")
    # box name needs to be unique on the system
    obj.vm.box = "preloaded-ciab-#{_name}"
    obj.vm.box_url = "file://" + Dir.pwd + "/#{preloaded_dir}/preloaded/preloaded-#{_name}.box"
    if Vagrant.has_plugin?('vagrant-vbguest')
      # do not update additions when booting this machine
      obj.vbguest.auto_update = false
    end
  else
    obj.vm.box = name
  end
end

