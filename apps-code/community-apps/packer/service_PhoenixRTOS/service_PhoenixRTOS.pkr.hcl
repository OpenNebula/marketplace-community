#include "common.pkr.hcl"

locals {
  # disk sizes (in MB) for each version
  disk_size = lookup({
    "phoenix"         = 8192,
    "phoenix.aarch64" = 3072,
  }, var.version, 0)
}

# 1) Build cloud-init ISO
source "null" "create_iso" {
  communicator = "none"
}

build {
  name    = "create_iso"
  sources = ["source.null.create_iso"]

  provisioner "shell-local" {
    inline = [
      "cloud-localds ${var.input_dir}/${var.appliance_name}-cloud-init.iso ${var.input_dir}/cloud-init.yml"
    ]
  }
}

# 2) Base Ubuntu Jammy VM
source "qemu" "service_PhoenixRTOS" {
  cpus             = 2
  cpu_model        = "host"
  memory           = 2048
  accelerator      = "kvm"

  iso_url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  iso_checksum     = "sha256:3c35baa64e58e594e523be5c61fa5f18efdfbc1be3d96a4211fd19e0b3f295e0"

  headless         = var.headless
  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  skip_resize_disk = local.disk_size == 0
  disk_size        = local.disk_size == 0 ? null : local.disk_size
  output_directory = var.output_dir

  qemuargs = [
    ["-cdrom", "${var.input_dir}/${var.appliance_name}-cloud-init.iso"],
    ["-serial", "stdio"],
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = var.appliance_name
}

# 3) Provision: one-context + Docker + pre-pull Phoenix-RTOS
build {
  name    = "service_PhoenixRTOS"
  sources = ["source.qemu.service_PhoenixRTOS"]

  provisioner "shell" {
    inline = [
      "set -eux",

      # make sure /context exists for the common install hook
      "mkdir -p /context",

      # force IPv4
      "printf 'Acquire::ForceIPv4 \"true\";\\n' >/etc/apt/apt.conf.d/99force-ipv4",

      # drop cloud-init
      "apt-get update -y",
      "DEBIAN_FRONTEND=noninteractive apt-get purge -y cloud-init cloud-initramfs-growroot || true",

      # install one-context + its deps
      "apt-get install -y wget cloud-image-utils cloud-utils ruby ifupdown qemu-guest-agent virt-what",
      "wget -qO /tmp/one-context.deb https://github.com/OpenNebula/one-apps/releases/download/v6.10.0-3/one-context_6.10.0-3.deb",
      "dpkg -i /tmp/one-context.deb || apt-get install -fy",
      "rm -f /tmp/one-context.deb",
      "systemctl enable one-context.service",

      # Docker prereqs
      "apt-get update -y",
      "apt-get install -y ca-certificates curl gnupg",

      # add Docker’s GPG key
      "install -d -m0755 /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "chmod a+r /etc/apt/keyrings/docker.gpg",

      # configure Docker repo (no HCL interpolation in here)
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable\" | tee /etc/apt/sources.list.d/docker.list",

      # install Docker
      "apt-get update -y",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "systemctl enable --now docker",

      # bake in the container
      "docker pull pablodelarco/phoenix-rtos-one:latest"
    ]
  }

  # copy your context binaries & scripts
  provisioner "file" {
    source      = "context-linux/out/"
    destination = "/context"
  }
  provisioner "file" {
    source      = "${path.root}/../../appliances/PhoenixRTOS/appliance.sh"
    destination = "/tmp/appliance.sh"
  }
  provisioner "file" {
    source      = "${path.root}/../../appliances/service.sh"
    destination = "/tmp/service.sh"
  }
  provisioner "file" {
    source      = "${path.root}/../../appliances/lib"
    destination = "/tmp/lib"
  }

  # run the numbered appliance scripts
  provisioner "shell" {
    execute_command   = "sudo -iu root {{.Vars}} bash {{.Path}}"
    scripts           = sort(concat(
      [for s in fileset(".", "*.sh")               : "${var.input_dir}/${s}"],
      [for s in fileset(".", "*.sh.${var.version}") : "${var.input_dir}/${s}"]
    ))
    expect_disconnect = true
  }

  post-processor "shell-local" {
    scripts          = ["packer/postprocess.sh"]
    execute_command  = ["bash","-c","{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
  }
}
