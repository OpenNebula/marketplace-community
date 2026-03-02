source "null" "null" { communicator = "none" }

# Prior to setting up the appliance, the context packages need to be generated first
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

# Build VM image using QEMU
source "qemu" "prowler" {
  cpus        = 2
  memory      = 8192
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
  disk_size        = "20480"

  output_directory = var.output_dir

  qemuargs = [
    ["-serial", "stdio"],
    ["-cpu", "host"],
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    # MAC addr needs to match ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = "${var.appliance_name}"
}

build {
  sources = ["source.qemu.prowler"]

  # Revert insecure SSH options done by context start_script
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]
  }

  # Create directory structure for appliance scripts
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Copy appliance management scripts
  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  # Copy bash libraries
  provisioner "file" {
    sources = [
      "../../lib/common.sh",
      "../../lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  # Copy appliance service manager
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  # Copy Prowler appliance script
  provisioner "file" {
    sources     = ["../../appliances/prowler/appliance.sh"]
    destination = "/etc/one-appliance/service.d/"
  }

  # Configure context
  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  # Execute install step
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Post-process: clean up machine ID, etc.
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
