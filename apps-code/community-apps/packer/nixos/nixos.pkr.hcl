source "qemu" "nixos" {
  cpus        = 1
  memory      = 2048
  accelerator = "kvm"

  iso_url      = lookup(lookup(var.nixos, var.arch, {}), "iso_url", "")
  iso_checksum = "none"

  headless = var.headless

  firmware     = lookup(lookup(var.arch_vars, var.arch, {}), "firmware", "")
  use_pflash   = lookup(lookup(var.arch_vars, var.arch, {}), "use_pflash", "")
  machine_type = lookup(lookup(var.arch_vars, var.arch, {}), "machine_type", "")
  qemu_binary  = lookup(lookup(var.arch_vars, var.arch, {}), "qemu_binary", "")

  disk_image       = false
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  skip_resize_disk = false
  disk_size        = 10240

  qemuargs = [
    ["-cpu", "host"],
    ["-serial", "stdio"],
  ]

  boot_wait = "5s"
  boot_command = [
    "<enter><wait30s>",
    "sudo chpasswd <<< root:opennebula<enter>",
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "900s"
  shutdown_command = "poweroff"
  vm_name          = "${var.appliance_name}"

  output_directory = var.output_dir
}

locals {
  version_no_arch = split(".", var.version).0
}

build {
  sources = ["source.qemu.nixos"]

  provisioner "shell" {
    execute_command = "sudo -iu root {{.Vars}} bash {{.Path}}"
    environment_vars = [
      "ARCH=${var.arch}",
      "ALT_ARCH=${lookup(lookup(var.nixos, var.arch, {}), "alt_arch", "")}",
    ]
    # execute *.sh + *.sh.<version_no_arch> from input_dir
    scripts = sort(concat(
      [for s in fileset(".", "[0-9][0-9]-*.sh") : "${var.input_dir}/${s}"],
      [for s in fileset(".", "[0-9][0-9]-*.sh.${local.version_no_arch}") : "${var.input_dir}/${s}"]
    ))
    expect_disconnect = true
  }

  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=${var.output_dir}",
      "APPLIANCE_NAME=${var.appliance_name}",
    ]
    scripts = ["packer/nixos/postprocess.sh"]
  }
}
