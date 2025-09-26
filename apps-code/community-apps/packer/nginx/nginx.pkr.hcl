packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "nginx" {
  accelerator      = "kvm"
  boot_command     = ["<enter><wait><f6><esc><wait> ", "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ", "--- <enter>"]
  boot_wait        = "5s"
  disk_size        = "8192M"
  format           = "qcow2"
  headless         = var.headless
  http_directory   = var.input_dir
  iso_checksum     = "file:https://releases.ubuntu.com/jammy/SHA256SUMS"
  iso_url          = "https://releases.ubuntu.com/jammy/ubuntu-22.04.4-live-server-amd64.iso"
  memory           = 2048
  net_device       = "virtio-net"
  output_directory = var.output_dir
  qemuargs         = [["-cpu", "host"]]
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
  ssh_password     = "packer"
  ssh_timeout     = "60m"
  ssh_username     = "packer"
  vm_name          = var.appliance_name
}

build {
  sources = ["source.qemu.nginx"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "../one-apps/packer/10-upgrade-distro.sh",
      "../one-apps/packer/11-update-grub.sh",
      "../one-apps/packer/80-install-context.sh",
      "../one-apps/packer/81-configure-ssh.sh",
      "82-configure-context.sh",
      "../one-apps/packer/90-install-nginx-appliance.sh",
      "../one-apps/packer/98-collect-garbage.sh"
    ]
  }

  post-processor "shell-local" {
    script = "postprocess.sh"
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}"
    ]
  }
}
