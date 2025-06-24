variable "appliance_name" {
  type    = string
  default = "nixos"
}

variable "version" {
  type    = string
  default = "2505"
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type    = bool
  default = false
}

variable "nixos" {
  type = map(map(string))
  default = {
    "x86_64" = {
      iso_url  = "https://releases.nixos.org/nixos/25.05/nixos-25.05.803297.10d7f8d34e5e/nixos-minimal-25.05.803297.10d7f8d34e5e-x86_64-linux.iso"
      arch     = "x86_64"
      alt_arch = "amd64"
    }

    "aarch64" = {
      iso_url  = "https://releases.nixos.org/nixos/25.05/nixos-25.05.803297.10d7f8d34e5e/nixos-minimal-25.05.803297.10d7f8d34e5e-aarch64-linux.iso"
      arch     = "aarch64"
      alt_arch = "arm64"
    }
  }
}
