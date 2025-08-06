source "null" "null" { communicator = "none" }

# Prior to setting up the appliance or distro, the context packages need to be generated first
# These will then be installed as part of the setup process
build {
  sources = ["source.null.null"]

  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.input_dir}/context",
      "${var.input_dir}/gen_context > ${var.input_dir}/context/context.sh",
      "mkisofs -o ${var.input_dir}/${var.appliance_name}-context.iso -V CONTEXT -J -R ${var.input_dir}/context",
    ]
  }
}

# A Virtual Machine is created with qemu in order to run the setup from the ISO on the CD-ROM
# Here are the details about the VM virtual hardware
source "qemu" "srsran" {
  cpus        = 6
  memory      = 16384
  accelerator = "kvm"

  iso_url      = "../one-apps/export/ubuntu2404.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "80G"

  output_directory = var.output_dir

  qemuargs = [["-serial", "stdio"],
    ["-cpu", "host"],
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    # MAC addr needs to match ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]
  ssh_username          = "root"
  ssh_password          = "opennebula"
  ssh_wait_timeout      = "1200s"  # Increased to 20 minutes
  ssh_timeout           = "10m"    # Individual SSH connection timeout
  shutdown_command      = "poweroff"
  vm_name               = "${var.appliance_name}"
}

# Once the VM launches the following logic will be executed inside it to customize what happens inside
# Essentially, a bunch of scripts are pulled from ./appliances and placed inside the Guest OS
# There are shared libraries for ruby and bash. Bash is used in this srsRAN appliance
build {
  sources = ["source.qemu.srsran"]

  # revert insecure ssh options done by context start_script
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]
  }

  ##############################################
  # BEGIN placing script logic inside Guest OS #
  ##############################################

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Scripts Required by a further step
  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  # Contains the appliance service management tool
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  # Bash library for easier custom implementation in bash logic
  provisioner "file" {
    sources = [
      "../one-apps/appliances/lib/common.sh",
      "../one-apps/appliances/lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  # Pull your own custom logic here
  provisioner "file" {
    source      = "../../appliances/srsran/appliance.sh" # location of the file in the git repo. Flexible
    destination = "/etc/one-appliance/service.d/appliance.sh" # path in the Guest OS. Strict, always the same
  }

  # Copy srsRAN management scripts
  provisioner "file" {
    sources = [
      "${var.input_dir}/scripts/start.sh",
      "${var.input_dir}/scripts/stop.sh",
      "${var.input_dir}/scripts/show_configuration.sh",
    ]
    destination = "/tmp/"
  }

  # Install management scripts with proper permissions
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx /tmp/start.sh /usr/local/bin/",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx /tmp/stop.sh /usr/local/bin/",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx /tmp/show_configuration.sh /usr/local/bin/",
      "rm -f /tmp/start.sh /tmp/stop.sh /tmp/show_configuration.sh",
    ]
  }

  # Create directory for predefined configuration files
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "mkdir -p /tmp/srsran_configs",
    ]
  }

  # Copy predefined configuration files
  provisioner "file" {
    source      = "${var.input_dir}/configs/"
    destination = "/tmp/srsran_configs/"
  }

  # Install predefined configuration files
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "mkdir -p /etc/srsran/pre-defined-configs",
      "cp -r /tmp/srsran_configs/* /etc/srsran/pre-defined-configs/",
      "chown -R root:root /etc/srsran/pre-defined-configs",
      "chmod -R 644 /etc/srsran/pre-defined-configs/*.yaml",
      "rm -rf /tmp/srsran_configs",
    ]
  }

  # Copy PHC2SYS service file for VM clock synchronization
  provisioner "file" {
    source      = "${var.input_dir}/phc2sys.service"
    destination = "/tmp/phc2sys.service"
  }

  # Install PHC2SYS service file
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "echo 'Installing PHC2SYS service file...'",
      "ls -la /tmp/phc2sys.service",
      "install -o 0 -g 0 -m 644 /tmp/phc2sys.service /etc/systemd/system/",
      "echo 'Verifying installation...'",
      "ls -la /etc/systemd/system/phc2sys.service",
      "rm -f /tmp/phc2sys.service",
      "echo 'PHC2SYS service file installation completed.'",
    ]
  }

  #######################################################################
  # RT Kernel Installation (before main appliance setup)               #
  #######################################################################

  # Create directory for RT kernel packages
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "mkdir -p /etc/rt-kernel-packages",
      "echo 'Created /etc/rt-kernel-packages directory'",
    ]
  }

  # Copy pre-built RT kernel packages if they exist
  provisioner "file" {
    source      = "packer/srsran/kernel_pkgs/"
    destination = "/etc/rt-kernel-packages/"
  }

  # Copy RT kernel installation script
  provisioner "file" {
    source      = "packer/srsran/install_rt_kernel.sh"
    destination = "/tmp/install_rt_kernel.sh"
  }

  # Execute RT kernel installation
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "echo 'Starting RT kernel installation...'",
      "chmod +x /tmp/install_rt_kernel.sh",
      "/tmp/install_rt_kernel.sh",
      "rm -f /tmp/install_rt_kernel.sh",
      "echo 'RT kernel installation completed. System will reboot to activate RT kernel.'",
    ]
  }

  # Reboot to activate RT kernel
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "echo 'Rebooting to activate RT kernel...'",
      "sync",
      "reboot",
    ]
    expect_disconnect = true
  }

  # Wait for system to come back up with RT kernel
  provisioner "shell" {
    pause_before = "30s"
    inline_shebang = "/bin/bash -e"
    inline = [
      "echo 'System rebooted. Verifying RT kernel is active...'",
      "uname -r",
      "if [[ \"$(uname -r)\" == *\"rt\"* ]]; then",
      "  echo 'SUCCESS: RT kernel is now active'",
      "else",
      "  echo 'WARNING: RT kernel may not be active yet'",
      "  echo 'Current kernel: '$(uname -r)",
      "fi",
    ]
  }

  #######################################################################
  # Setup appliance: Execute install step                               #
  # https://github.com/OpenNebula/one-apps/wiki/apps_intro#installation #
  #######################################################################

  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Remove machine ID from the VM and get it ready for continuous cloud use
  # https://github.com/OpenNebula/one-apps/wiki/tool_dev#appliance-build-process
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["packer/postprocess.sh"]
  }
}
