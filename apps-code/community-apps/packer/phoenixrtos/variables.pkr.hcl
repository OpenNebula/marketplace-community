variable "appliance_name" {
  type    = string
  default = "phoenixrtos"
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

variable "version" {
  type    = string
  default = ""
}

variable "arch" {
  type    = string
  default = "x86_64"
}
