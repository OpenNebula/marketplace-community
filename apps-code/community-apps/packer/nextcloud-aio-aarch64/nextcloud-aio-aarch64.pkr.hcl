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

# Build VM image (aarch64 / arm64).
# Boots the one-apps Ubuntu 24.04 aarch64 base image natively with
# qemu-system-aarch64 + KVM + UEFI (AAVMF) on the ARM "virt" machine.
# MUST be built on a real arm64 KVM host (x86 hosts can only TCG-emulate, ~hours).
source "qemu" "nextcloud-aio-aarch64" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  # aarch64-specific QEMU wiring (mirrors one-apps packer arch_vars for aarch64)
  qemu_binary  = "/usr/bin/qemu-system-aarch64"
  machine_type = "virt,gic-version=max"
  firmware     = "/usr/share/AAVMF/AAVMF_CODE.fd"
  use_pflash   = false
  cpu_model    = "host"

  iso_url      = "../one-apps/export/ubuntu2404.aarch64.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "8000"

  output_directory = var.output_dir

  qemuargs = [
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-context.iso"],
    ["-serial", "stdio"],
    # MAC addr needs to match ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout     = "900s"
  shutdown_command = "poweroff"
  vm_name          = var.appliance_name
}

build {
  sources = ["source.qemu.nextcloud-aio-aarch64"]

  # revert insecure ssh options done by context start_script
  provisioner "shell" {
    scripts = ["${var.input_dir}/81-configure-ssh.sh"]
  }

  # Ubuntu 24.04: needrestart hooks apt and restarts ssh.service mid-provision,
  # dropping Packer's SSH connection. Remove it before any package / service work.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get remove -y needrestart || true",
    ]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

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
  provisioner "file" {
    sources     = ["../../appliances/nextcloud-aio-aarch64/appliance.sh"]
    destination = "/etc/one-appliance/service.d/"
  }

  provisioner "shell" {
    scripts = ["${var.input_dir}/82-configure-context.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Clean build-time network artifacts. The build contextualizes with
  # NETCFG_TYPE=nm (NetworkManager) so apt/docker have network, which persists a
  # NetworkManager netplan connection (/etc/netplan/90-NM-*.yaml) into the image.
  # At runtime one-context writes a networkd config (/etc/netplan/50-one-context.yaml);
  # the two renderers then fight over eth0 and it never gets its IP. Remove the
  # baked-in network config so the first runtime boot configures eth0 cleanly.
  # Do NOT run `netplan apply` here: that would drop the build SSH connection;
  # the clean state takes effect on the next (runtime) boot.
  provisioner "shell" {
    inline_shebang = "/bin/bash"
    inline = [
      "rm -f /etc/netplan/90-NM-*.yaml /etc/netplan/50-one-context.yaml",
      "rm -f /etc/NetworkManager/system-connections/* 2>/dev/null || true",
      "sync",
    ]
  }

  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
