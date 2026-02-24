# Build 1: Generate cloud-init seed ISO
source "null" "context" {
  communicator = "none"
}

build {
  name    = "context"
  sources = ["source.null.context"]

  provisioner "shell-local" {
    inline = [
      "cloud-localds ${var.input_dir}/${var.appliance_name}-cloud-init.iso ${var.input_dir}/cloud-init.yml",
    ]
  }
}

# Build 2: Provision the SLM-Copilot QCOW2 image
source "qemu" "slm_copilot" {
  accelerator = "kvm"

  cpus      = 4
  memory    = 32768
  disk_size = "60G"

  iso_url      = "../one-apps/export/ubuntu2404.qcow2"
  iso_checksum = "none"
  disk_image   = true

  output_directory = var.output_dir
  vm_name          = "${var.appliance_name}"
  format           = "qcow2"

  headless = var.headless

  net_device     = "virtio-net"
  disk_interface = "virtio"

  qemuargs = [
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-cloud-init.iso"],
    ["-serial", "mon:stdio"],
    ["-cpu", "host"],
  ]

  boot_wait = "30s"

  communicator     = "ssh"
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "30m"
  ssh_wait_timeout = "1800s"

  shutdown_command = "poweroff"
}

build {
  name    = "slm-copilot"
  sources = ["source.qemu.slm_copilot"]

  # Step 1: SSH hardening
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]
  }

  # Step 2: Install one-context package
  provisioner "shell" {
    inline = ["mkdir -p /context"]
  }

  provisioner "file" {
    source      = "../one-apps/context-linux/out/"
    destination = "/context"
  }

  provisioner "shell" {
    scripts = ["${var.input_dir}/80-install-context.sh"]
  }

  # Step 3: Create one-appliance directory structure
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Step 4: Install one-apps framework files
  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  provisioner "file" {
    sources = [
      "../../lib/common.sh",
      "../../lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }

  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  provisioner "shell" {
    inline = ["chmod 0755 /etc/one-appliance/service"]
  }

  # Step 5: Install SLM-Copilot appliance script
  provisioner "file" {
    sources     = ["../../appliances/slm-copilot/appliance.sh"]
    destination = "/etc/one-appliance/service.d/"
  }

  # Step 6: Move context hooks into place
  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  # Step 7: Run service_install (downloads binary, model, pre-warms)
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Step 8: Cleanup for cloud reuse
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get purge -y cloud-init snapd fwupd || true",
      "apt-get autoremove -y --purge || true",
      "apt-get clean -y",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/sysctl.d/99-cloudimg-ipv6.conf",
      "rm -rf /context/",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "rm -rf /tmp/* /var/tmp/*",
      "sync",
    ]
  }

  # Post-process: sparsify and compress image
  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
