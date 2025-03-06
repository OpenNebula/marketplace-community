# null source, equivalent as applying configuration into localhost.
source "null" "null" { communicator = "none" }

# This SETUP build step targets localhost
build {
  sources = ["source.null.null"]

  # Generate temporal CONTEXT .iso file to be able to login into the source VM.
  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.input_dir}/context",
      "${var.input_dir}/gen_context > ${var.input_dir}/context/context.sh",
      "mkisofs -o ${var.input_dir}/${var.appliance_name}-context.iso -V CONTEXT -J -R ${var.input_dir}/context",
    ]
  }
}


# QEMU sets up a temporal VM from a base .qcow2/.raw image, with the specified resources. 
source "qemu" "example" {
  cpus        = 2 
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/ubuntu2204.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  skip_resize_disk = true           # You can either 'skip_resize_disk = true' to use the "virtual disk" of the original image, or set a fixed disk_size
  #disk_size        = "10240"       # I recommend the second approach as usually the original image is not large enough to fit all the added libraries and binaries.

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    ["-serial", "stdio"],
    # MAC addr needs to mach ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = "${var.appliance_name}"
}

# This INSTALL build step targets the temporal QEMU VM.
# Essentially, a bunch of scripts are pulled from ./appliances and placed inside the Guest OS
# There are shared libraries for ruby and bash. bash is used in this example.
build {
  sources = ["source.qemu.example"]

  # Revert the insecure ssh configuration aplied by the by the initial 'shell-local' in order to be able to log in to the VM
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]       # Set /etc/ssh/sshd_config with: PasswordAuthentication no, PermitRootLogin without-password, UseDNS no
  }

  # Create directories for the new appliance files.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Import network configuration scripts for OpenNebula CONTEXT.
  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",     # Script to run '/etc/one-appliance/service configure' and 'bootstrap'.
      "../one-apps/appliances/scripts/net-99-report-ready",          # When $REPORT_READY is YES, run 'onegate vm update --data READY=YES' or a curl/wget equivalent.
    ]
    destination = "/etc/one-appliance/"
  }

  # Import bash libraries scripts with multiple custom functions for appliances.
  provisioner "file" {
    sources = [
      "../one-apps/appliances/lib/common.sh",
      "../one-apps/appliances/lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  # Import the appliance service management script, which invokes the previous functions.
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle  
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }
  
  #################################################################################################
  ###  BEGIN BLOCK:      'example'-specific steps to configure the appliance   ####################
  #################################################################################################

  provisioner "file" {
    sources     = [                                   # locations of the file in the git repo. Flexible
      "appliances/.example/appliance.sh",                   # main configuration script.
      "appliances/.example/jenkins_plugins.txt",            # sample .txt file to import.
      "appliances/.example/jobs.yaml",                      # sample .yaml file to import.
      ]
    destination = "/etc/one-appliance/service.d/"          # path in the Guest OS. Strict, always the same
  }


  #################################################################################################
  ###  END BLOCK:      'example'-specific steps to configure the appliance   ######################
  #################################################################################################

  # Move files net-*0 and net-99 to /etc/one-context and edit their permissions.
  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  # Run the previously imported appliance service management script, which rus the 'install()' function of your appliance.sh file.
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#installation
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Remove the machine ID from the VM and prepare it for cloud-continuum usage.
  # https://github.com/OpenNebula/one-apps/wiki/tool_dev#appliance-build-process
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
