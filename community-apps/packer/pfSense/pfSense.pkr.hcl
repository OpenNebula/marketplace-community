# Download and uncompress the .iso.gz image
source "local" "download_iso" {
  communicator = "none"
  iso_url      = lookup(var.pfSense[var.version]["iso_url"], {})
  target_path  = "./${var.appliance_name}-${var.version}.iso.gz"
}

build {
  sources = ["source.local.download_iso"]

  provisioner "shell-local" {
    inline = [
      "echo 'Downloading ISO from ${var.iso_url}'",
      "curl -o ${var.target_path} ${var.iso_url}"
    ]
  }

  provisioner "shell-local" {
    inline = [
      "echo 'Decompressing ISO'",
      "gunzip -kf ${var.target_path}"
    ]
  }
}


# Build VM image
source "qemu" "freebsd" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "./${var.appliance_name}-${var.version}.iso.gz"
  # iso_checksum = var.pfSense[var.version]["iso_checksum"]

  headless = var.headless

  boot_wait    = "240s"
  boot_command = lookup(var.boot_cmd, var.version, [])

  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = 4096

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-serial", "stdio"],
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = "${var.appliance_name}"
}

build {
  sources = ["source.qemu.freebsd"]

  # be carefull with shell inline provisioners, FreeBSD csh is tricky
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
    scripts         = ["${var.input_dir}/mkdir"]
  }

  provisioner "file" {
    destination = "/tmp/context"
    source      = "context-linux/out/"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
    scripts         = ["${var.input_dir}/script.sh"]
  }
}
